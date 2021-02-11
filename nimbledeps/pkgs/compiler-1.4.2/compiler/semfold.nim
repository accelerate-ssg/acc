#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# this module folds constants; used by semantic checking phase
# and evaluation phase

import
  strutils, options, ast, trees, nimsets,
  platform, math, msgs, idents, renderer, types,
  commands, magicsys, modulegraphs, strtabs, lineinfos

proc errorType*(g: ModuleGraph): PType =
  ## creates a type representing an error state
  result = newType(tyError, g.owners[^1])
  result.flags.incl tfCheckedForDestructor

proc newIntNodeT*(intVal: Int128, n: PNode; g: ModuleGraph): PNode =
  result = newIntTypeNode(intVal, n.typ)
  # See bug #6989. 'pred' et al only produce an int literal type if the
  # original type was 'int', not a distinct int etc.
  if n.typ.kind == tyInt:
    # access cache for the int lit type
    result.typ = getIntLitType(g, result)
  result.info = n.info

proc newFloatNodeT*(floatVal: BiggestFloat, n: PNode; g: ModuleGraph): PNode =
  if n.typ.skipTypes(abstractInst).kind == tyFloat32:
    result = newFloatNode(nkFloat32Lit, floatVal)
  else:
    result = newFloatNode(nkFloatLit, floatVal)
  result.typ = n.typ
  result.info = n.info

proc newStrNodeT*(strVal: string, n: PNode; g: ModuleGraph): PNode =
  result = newStrNode(nkStrLit, strVal)
  result.typ = n.typ
  result.info = n.info

proc getConstExpr*(m: PSym, n: PNode; g: ModuleGraph): PNode
  # evaluates the constant expression or returns nil if it is no constant
  # expression
proc evalOp*(m: TMagic, n, a, b, c: PNode; g: ModuleGraph): PNode

proc checkInRange(conf: ConfigRef; n: PNode, res: Int128): bool =
  res in firstOrd(conf, n.typ)..lastOrd(conf, n.typ)

proc foldAdd(a, b: Int128, n: PNode; g: ModuleGraph): PNode =
  let res = a + b
  if checkInRange(g.config, n, res):
    result = newIntNodeT(res, n, g)

proc foldSub(a, b: Int128, n: PNode; g: ModuleGraph): PNode =
  let res = a - b
  if checkInRange(g.config, n, res):
    result = newIntNodeT(res, n, g)

proc foldUnarySub(a: Int128, n: PNode, g: ModuleGraph): PNode =
  if a != firstOrd(g.config, n.typ):
    result = newIntNodeT(-a, n, g)

proc foldAbs(a: Int128, n: PNode; g: ModuleGraph): PNode =
  if a != firstOrd(g.config, n.typ):
    result = newIntNodeT(abs(a), n, g)

proc foldMul(a, b: Int128, n: PNode; g: ModuleGraph): PNode =
  let res = a * b
  if checkInRange(g.config, n, res):
    return newIntNodeT(res, n, g)

proc ordinalValToString*(a: PNode; g: ModuleGraph): string =
  # because $ has the param ordinal[T], `a` is not necessarily an enum, but an
  # ordinal
  var x = getInt(a)

  var t = skipTypes(a.typ, abstractRange)
  case t.kind
  of tyChar:
    result = $chr(toInt64(x) and 0xff)
  of tyEnum:
    var n = t.n
    for i in 0..<n.len:
      if n[i].kind != nkSym: internalError(g.config, a.info, "ordinalValToString")
      var field = n[i].sym
      if field.position == x:
        if field.ast == nil:
          return field.name.s
        else:
          return field.ast.strVal
    localError(g.config, a.info,
      "Cannot convert int literal to $1. The value is invalid." %
        [typeToString(t)])
  else:
    result = $x

proc isFloatRange(t: PType): bool {.inline.} =
  result = t.kind == tyRange and t[0].kind in {tyFloat..tyFloat128}

proc isIntRange(t: PType): bool {.inline.} =
  result = t.kind == tyRange and t[0].kind in {
      tyInt..tyInt64, tyUInt8..tyUInt32}

proc pickIntRange(a, b: PType): PType =
  if isIntRange(a): result = a
  elif isIntRange(b): result = b
  else: result = a

proc isIntRangeOrLit(t: PType): bool =
  result = isIntRange(t) or isIntLit(t)

proc makeRange(typ: PType, first, last: BiggestInt; g: ModuleGraph): PType =
  let minA = min(first, last)
  let maxA = max(first, last)
  let lowerNode = newIntNode(nkIntLit, minA)
  if typ.kind == tyInt and minA == maxA:
    result = getIntLitType(g, lowerNode)
  elif typ.kind in {tyUInt, tyUInt64}:
    # these are not ordinal types, so you get no subrange type for these:
    result = typ
  else:
    var n = newNode(nkRange)
    n.add lowerNode
    n.add newIntNode(nkIntLit, maxA)
    result = newType(tyRange, typ.owner)
    result.n = n
    addSonSkipIntLit(result, skipTypes(typ, {tyRange}))

proc makeRangeF(typ: PType, first, last: BiggestFloat; g: ModuleGraph): PType =
  var n = newNode(nkRange)
  n.add newFloatNode(nkFloatLit, min(first.float, last.float))
  n.add newFloatNode(nkFloatLit, max(first.float, last.float))
  result = newType(tyRange, typ.owner)
  result.n = n
  addSonSkipIntLit(result, skipTypes(typ, {tyRange}))

proc fitLiteral(c: ConfigRef, n: PNode): PNode {.deprecated: "no substitute".} =
  # Trim the literal value in order to make it fit in the destination type
  if n == nil:
    # `n` may be nil if the overflow check kicks in
    return

  doAssert n.kind in {nkIntLit, nkCharLit}

  result = n

  let typ = n.typ.skipTypes(abstractRange)
  if typ.kind in tyUInt..tyUInt32:
    result.intVal = result.intVal and castToInt64(lastOrd(c, typ))

proc evalOp(m: TMagic, n, a, b, c: PNode; g: ModuleGraph): PNode =
  # b and c may be nil
  result = nil
  case m
  of mOrd: result = newIntNodeT(getOrdValue(a), n, g)
  of mChr: result = newIntNodeT(getInt(a), n, g)
  of mUnaryMinusI, mUnaryMinusI64: result = foldUnarySub(getInt(a), n, g)
  of mUnaryMinusF64: result = newFloatNodeT(-getFloat(a), n, g)
  of mNot: result = newIntNodeT(One - getInt(a), n, g)
  of mCard: result = newIntNodeT(toInt128(nimsets.cardSet(g.config, a)), n, g)
  of mBitnotI:
    if n.typ.isUnsigned:
      result = newIntNodeT(bitnot(getInt(a)).maskBytes(int(n.typ.size)), n, g)
    else:
      result = newIntNodeT(bitnot(getInt(a)), n, g)
  of mLengthArray: result = newIntNodeT(lengthOrd(g.config, a.typ), n, g)
  of mLengthSeq, mLengthOpenArray, mLengthStr:
    if a.kind == nkNilLit:
      result = newIntNodeT(Zero, n, g)
    elif a.kind in {nkStrLit..nkTripleStrLit}:
      result = newIntNodeT(toInt128(a.strVal.len), n, g)
    else:
      result = newIntNodeT(toInt128(a.len), n, g)
  of mUnaryPlusI, mUnaryPlusF64: result = a # throw `+` away
  # XXX: Hides overflow/underflow
  of mAbsI: result = foldAbs(getInt(a), n, g)
  of mSucc: result = foldAdd(getOrdValue(a), getInt(b), n, g)
  of mPred: result = foldSub(getOrdValue(a), getInt(b), n, g)
  of mAddI: result = foldAdd(getInt(a), getInt(b), n, g)
  of mSubI: result = foldSub(getInt(a), getInt(b), n, g)
  of mMulI: result = foldMul(getInt(a), getInt(b), n, g)
  of mMinI:
    let argA = getInt(a)
    let argB = getInt(b)
    result = newIntNodeT(if argA < argB: argA else: argB, n, g)
  of mMaxI:
    let argA = getInt(a)
    let argB = getInt(b)
    result = newIntNodeT(if argA > argB: argA else: argB, n, g)
  of mShlI:
    case skipTypes(n.typ, abstractRange).kind
    of tyInt8: result = newIntNodeT(toInt128(toInt8(getInt(a)) shl toInt64(getInt(b))), n, g)
    of tyInt16: result = newIntNodeT(toInt128(toInt16(getInt(a)) shl toInt64(getInt(b))), n, g)
    of tyInt32: result = newIntNodeT(toInt128(toInt32(getInt(a)) shl toInt64(getInt(b))), n, g)
    of tyInt64: result = newIntNodeT(toInt128(toInt64(getInt(a)) shl toInt64(getInt(b))), n, g)
    of tyInt:
      if g.config.target.intSize == 4:
        result = newIntNodeT(toInt128(toInt32(getInt(a)) shl toInt64(getInt(b))), n, g)
      else:
        result = newIntNodeT(toInt128(toInt64(getInt(a)) shl toInt64(getInt(b))), n, g)
    of tyUInt8: result = newIntNodeT(toInt128(toUInt8(getInt(a)) shl toInt64(getInt(b))), n, g)
    of tyUInt16: result = newIntNodeT(toInt128(toUInt16(getInt(a)) shl toInt64(getInt(b))), n, g)
    of tyUInt32: result = newIntNodeT(toInt128(toUInt32(getInt(a)) shl toInt64(getInt(b))), n, g)
    of tyUInt64: result = newIntNodeT(toInt128(toUInt64(getInt(a)) shl toInt64(getInt(b))), n, g)
    of tyUInt:
      if g.config.target.intSize == 4:
        result = newIntNodeT(toInt128(toUInt32(getInt(a)) shl toInt64(getInt(b))), n, g)
      else:
        result = newIntNodeT(toInt128(toUInt64(getInt(a)) shl toInt64(getInt(b))), n, g)
    else: internalError(g.config, n.info, "constant folding for shl")
  of mShrI:
    var a = cast[uint64](getInt(a))
    let b = cast[uint64](getInt(b))
    # To support the ``-d:nimOldShiftRight`` flag, we need to mask the
    # signed integers to cut off the extended sign bit in the internal
    # representation.
    if 0'u64 < b: # do not cut off the sign extension, when there is
              # no bit shifting happening.
      case skipTypes(n.typ, abstractRange).kind
      of tyInt8: a = a and 0xff'u64
      of tyInt16: a = a and 0xffff'u64
      of tyInt32: a = a and 0xffffffff'u64
      of tyInt:
        if g.config.target.intSize == 4:
          a = a and 0xffffffff'u64
      else:
        # unsigned and 64 bit integers don't need masking
        discard
    let c = cast[BiggestInt](a shr b)
    result = newIntNodeT(toInt128(c), n, g)
  of mAshrI:
    case skipTypes(n.typ, abstractRange).kind
    of tyInt8: result =  newIntNodeT(toInt128(ashr(toInt8(getInt(a)), toInt8(getInt(b)))), n, g)
    of tyInt16: result = newIntNodeT(toInt128(ashr(toInt16(getInt(a)), toInt16(getInt(b)))), n, g)
    of tyInt32: result = newIntNodeT(toInt128(ashr(toInt32(getInt(a)), toInt32(getInt(b)))), n, g)
    of tyInt64, tyInt:
      result = newIntNodeT(toInt128(ashr(toInt64(getInt(a)), toInt64(getInt(b)))), n, g)
    else: internalError(g.config, n.info, "constant folding for ashr")
  of mDivI:
    let argA = getInt(a)
    let argB = getInt(b)
    if argB != Zero and (argA != firstOrd(g.config, n.typ) or argB != NegOne):
      result = newIntNodeT(argA div argB, n, g)
  of mModI:
    let argA = getInt(a)
    let argB = getInt(b)
    if argB != Zero and (argA != firstOrd(g.config, n.typ) or argB != NegOne):
      result = newIntNodeT(argA mod argB, n, g)
  of mAddF64: result = newFloatNodeT(getFloat(a) + getFloat(b), n, g)
  of mSubF64: result = newFloatNodeT(getFloat(a) - getFloat(b), n, g)
  of mMulF64: result = newFloatNodeT(getFloat(a) * getFloat(b), n, g)
  of mDivF64:
    result = newFloatNodeT(getFloat(a) / getFloat(b), n, g)
  of mIsNil: result = newIntNodeT(toInt128(ord(a.kind == nkNilLit)), n, g)
  of mLtI, mLtB, mLtEnum, mLtCh:
    result = newIntNodeT(toInt128(ord(getOrdValue(a) < getOrdValue(b))), n, g)
  of mLeI, mLeB, mLeEnum, mLeCh:
    result = newIntNodeT(toInt128(ord(getOrdValue(a) <= getOrdValue(b))), n, g)
  of mEqI, mEqB, mEqEnum, mEqCh:
    result = newIntNodeT(toInt128(ord(getOrdValue(a) == getOrdValue(b))), n, g)
  of mLtF64: result = newIntNodeT(toInt128(ord(getFloat(a) < getFloat(b))), n, g)
  of mLeF64: result = newIntNodeT(toInt128(ord(getFloat(a) <= getFloat(b))), n, g)
  of mEqF64: result = newIntNodeT(toInt128(ord(getFloat(a) == getFloat(b))), n, g)
  of mLtStr: result = newIntNodeT(toInt128(ord(getStr(a) < getStr(b))), n, g)
  of mLeStr: result = newIntNodeT(toInt128(ord(getStr(a) <= getStr(b))), n, g)
  of mEqStr: result = newIntNodeT(toInt128(ord(getStr(a) == getStr(b))), n, g)
  of mLtU:
    result = newIntNodeT(toInt128(ord(`<%`(toInt64(getOrdValue(a)), toInt64(getOrdValue(b))))), n, g)
  of mLeU:
    result = newIntNodeT(toInt128(ord(`<=%`(toInt64(getOrdValue(a)), toInt64(getOrdValue(b))))), n, g)
  of mBitandI, mAnd: result = newIntNodeT(bitand(a.getInt, b.getInt), n, g)
  of mBitorI, mOr: result = newIntNodeT(bitor(getInt(a), getInt(b)), n, g)
  of mBitxorI, mXor: result = newIntNodeT(bitxor(getInt(a), getInt(b)), n, g)
  of mAddU:
    let val = maskBytes(getInt(a) + getInt(b), int(n.typ.size))
    result = newIntNodeT(val, n, g)
  of mSubU:
    let val = maskBytes(getInt(a) - getInt(b), int(n.typ.size))
    result = newIntNodeT(val, n, g)
    # echo "subU: ", val, " n: ", n, " result: ", val
  of mMulU:
    let val = maskBytes(getInt(a) * getInt(b), int(n.typ.size))
    result = newIntNodeT(val, n, g)
  of mModU:
    let argA = maskBytes(getInt(a), int(a.typ.size))
    let argB = maskBytes(getInt(b), int(a.typ.size))
    if argB != Zero:
      result = newIntNodeT(argA mod argB, n, g)
  of mDivU:
    let argA = maskBytes(getInt(a), int(a.typ.size))
    let argB = maskBytes(getInt(b), int(a.typ.size))
    if argB != Zero:
      result = newIntNodeT(argA div argB, n, g)
  of mLeSet: result = newIntNodeT(toInt128(ord(containsSets(g.config, a, b))), n, g)
  of mEqSet: result = newIntNodeT(toInt128(ord(equalSets(g.config, a, b))), n, g)
  of mLtSet:
    result = newIntNodeT(toInt128(ord(
      containsSets(g.config, a, b) and not equalSets(g.config, a, b))), n, g)
  of mMulSet:
    result = nimsets.intersectSets(g.config, a, b)
    result.info = n.info
  of mPlusSet:
    result = nimsets.unionSets(g.config, a, b)
    result.info = n.info
  of mMinusSet:
    result = nimsets.diffSets(g.config, a, b)
    result.info = n.info
  of mConStrStr: result = newStrNodeT(getStrOrChar(a) & getStrOrChar(b), n, g)
  of mInSet: result = newIntNodeT(toInt128(ord(inSet(a, b))), n, g)
  of mRepr:
    # BUGFIX: we cannot eval mRepr here for reasons that I forgot.
    discard
  of mIntToStr, mInt64ToStr: result = newStrNodeT($(getOrdValue(a)), n, g)
  of mBoolToStr:
    if getOrdValue(a) == 0: result = newStrNodeT("false", n, g)
    else: result = newStrNodeT("true", n, g)
  of mFloatToStr: result = newStrNodeT($getFloat(a), n, g)
  of mCStrToStr, mCharToStr:
    if a.kind == nkBracket:
      var s = ""
      for b in a.sons:
        s.add b.getStrOrChar
      result = newStrNodeT(s, n, g)
    else:
      result = newStrNodeT(getStrOrChar(a), n, g)
  of mStrToStr: result = newStrNodeT(getStrOrChar(a), n, g)
  of mEnumToStr: result = newStrNodeT(ordinalValToString(a, g), n, g)
  of mArrToSeq:
    result = copyTree(a)
    result.typ = n.typ
  of mCompileOption:
    result = newIntNodeT(toInt128(ord(commands.testCompileOption(g.config, a.getStr, n.info))), n, g)
  of mCompileOptionArg:
    result = newIntNodeT(toInt128(ord(
      testCompileOptionArg(g.config, getStr(a), getStr(b), n.info))), n, g)
  of mEqProc:
    result = newIntNodeT(toInt128(ord(
        exprStructuralEquivalent(a, b, strictSymEquality=true))), n, g)
  else: discard

proc getConstIfExpr(c: PSym, n: PNode; g: ModuleGraph): PNode =
  result = nil
  for i in 0..<n.len:
    var it = n[i]
    if it.len == 2:
      var e = getConstExpr(c, it[0], g)
      if e == nil: return nil
      if getOrdValue(e) != 0:
        if result == nil:
          result = getConstExpr(c, it[1], g)
          if result == nil: return
    elif it.len == 1:
      if result == nil: result = getConstExpr(c, it[0], g)
    else: internalError(g.config, it.info, "getConstIfExpr()")

proc leValueConv*(a, b: PNode): bool =
  result = false
  case a.kind
  of nkCharLit..nkUInt64Lit:
    case b.kind
    of nkCharLit..nkUInt64Lit: result = a.getInt <= b.getInt
    of nkFloatLit..nkFloat128Lit: result = a.intVal <= round(b.floatVal).int
    else: result = false #internalError(a.info, "leValueConv")
  of nkFloatLit..nkFloat128Lit:
    case b.kind
    of nkFloatLit..nkFloat128Lit: result = a.floatVal <= b.floatVal
    of nkCharLit..nkUInt64Lit: result = a.floatVal <= toFloat64(b.getInt)
    else: result = false # internalError(a.info, "leValueConv")
  else: result = false # internalError(a.info, "leValueConv")

proc magicCall(m: PSym, n: PNode; g: ModuleGraph): PNode =
  if n.len <= 1: return

  var s = n[0].sym
  var a = getConstExpr(m, n[1], g)
  var b, c: PNode
  if a == nil: return
  if n.len > 2:
    b = getConstExpr(m, n[2], g)
    if b == nil: return
    if n.len > 3:
      c = getConstExpr(m, n[3], g)
      if c == nil: return
  result = evalOp(s.magic, n, a, b, c, g)

proc getAppType(n: PNode; g: ModuleGraph): PNode =
  if g.config.globalOptions.contains(optGenDynLib):
    result = newStrNodeT("lib", n, g)
  elif g.config.globalOptions.contains(optGenStaticLib):
    result = newStrNodeT("staticlib", n, g)
  elif g.config.globalOptions.contains(optGenGuiApp):
    result = newStrNodeT("gui", n, g)
  else:
    result = newStrNodeT("console", n, g)

proc rangeCheck(n: PNode, value: Int128; g: ModuleGraph) =
  if value < firstOrd(g.config, n.typ) or value > lastOrd(g.config, n.typ):
    localError(g.config, n.info, "cannot convert " & $value &
                                    " to " & typeToString(n.typ))

proc foldConv(n, a: PNode; g: ModuleGraph; check = false): PNode =
  let dstTyp = skipTypes(n.typ, abstractRange - {tyTypeDesc})
  let srcTyp = skipTypes(a.typ, abstractRange - {tyTypeDesc})

  # if srcTyp.kind == tyUInt64 and "FFFFFF" in $n:
  #   echo "n: ", n, " a: ", a
  #   echo "from: ", srcTyp, " to: ", dstTyp, " check: ", check
  #   echo getInt(a)
  #   echo high(int64)
  #   writeStackTrace()
  case dstTyp.kind
  of tyBool:
    case srcTyp.kind
    of tyFloat..tyFloat64:
      result = newIntNodeT(toInt128(getFloat(a) != 0.0), n, g)
    of tyChar, tyUInt..tyUInt64, tyInt..tyInt64:
      result = newIntNodeT(toInt128(a.getOrdValue != 0), n, g)
    of tyBool, tyEnum: # xxx shouldn't we disallow `tyEnum`?
      result = a
      result.typ = n.typ
    else: doAssert false, $srcTyp.kind
  of tyInt..tyInt64, tyUInt..tyUInt64:
    case srcTyp.kind
    of tyFloat..tyFloat64:
      result = newIntNodeT(toInt128(getFloat(a)), n, g)
    of tyChar, tyUInt..tyUInt64, tyInt..tyInt64:
      var val = a.getOrdValue
      if check: rangeCheck(n, val, g)
      result = newIntNodeT(val, n, g)
      if dstTyp.kind in {tyUInt..tyUInt64}:
        result.transitionIntKind(nkUIntLit)
    else:
      result = a
      result.typ = n.typ
    if check and result.kind in {nkCharLit..nkUInt64Lit}:
      rangeCheck(n, getInt(result), g)
  of tyFloat..tyFloat64:
    case srcTyp.kind
    of tyInt..tyInt64, tyEnum, tyBool, tyChar:
      result = newFloatNodeT(toFloat64(getOrdValue(a)), n, g)
    else:
      result = a
      result.typ = n.typ
  of tyOpenArray, tyVarargs, tyProc, tyPointer:
    discard
  else:
    result = a
    result.typ = n.typ

proc getArrayConstr(m: PSym, n: PNode; g: ModuleGraph): PNode =
  if n.kind == nkBracket:
    result = n
  else:
    result = getConstExpr(m, n, g)
    if result == nil: result = n

proc foldArrayAccess(m: PSym, n: PNode; g: ModuleGraph): PNode =
  var x = getConstExpr(m, n[0], g)
  if x == nil or x.typ.skipTypes({tyGenericInst, tyAlias, tySink}).kind == tyTypeDesc:
    return

  var y = getConstExpr(m, n[1], g)
  if y == nil: return

  var idx = toInt64(getOrdValue(y))
  case x.kind
  of nkPar, nkTupleConstr:
    if idx >= 0 and idx < x.len:
      result = x.sons[idx]
      if result.kind == nkExprColonExpr: result = result[1]
    else:
      localError(g.config, n.info, formatErrorIndexBound(idx, x.len-1) & $n)
  of nkBracket:
    idx -= toInt64(firstOrd(g.config, x.typ))
    if idx >= 0 and idx < x.len: result = x[int(idx)]
    else: localError(g.config, n.info, formatErrorIndexBound(idx, x.len-1) & $n)
  of nkStrLit..nkTripleStrLit:
    result = newNodeIT(nkCharLit, x.info, n.typ)
    if idx >= 0 and idx < x.strVal.len:
      result.intVal = ord(x.strVal[int(idx)])
    else:
      localError(g.config, n.info, formatErrorIndexBound(idx, x.strVal.len-1) & $n)
  else: discard

proc foldFieldAccess(m: PSym, n: PNode; g: ModuleGraph): PNode =
  # a real field access; proc calls have already been transformed
  var x = getConstExpr(m, n[0], g)
  if x == nil or x.kind notin {nkObjConstr, nkPar, nkTupleConstr}: return

  var field = n[1].sym
  for i in ord(x.kind == nkObjConstr)..<x.len:
    var it = x[i]
    if it.kind != nkExprColonExpr:
      # lookup per index:
      result = x[field.position]
      if result.kind == nkExprColonExpr: result = result[1]
      return
    if it[0].sym.name.id == field.name.id:
      result = x[i][1]
      return
  localError(g.config, n.info, "field not found: " & field.name.s)

proc foldConStrStr(m: PSym, n: PNode; g: ModuleGraph): PNode =
  result = newNodeIT(nkStrLit, n.info, n.typ)
  result.strVal = ""
  for i in 1..<n.len:
    let a = getConstExpr(m, n[i], g)
    if a == nil: return nil
    result.strVal.add(getStrOrChar(a))

proc newSymNodeTypeDesc*(s: PSym; info: TLineInfo): PNode =
  result = newSymNode(s, info)
  if s.typ.kind != tyTypeDesc:
    result.typ = newType(tyTypeDesc, s.owner)
    result.typ.addSonSkipIntLit(s.typ)
  else:
    result.typ = s.typ

proc getConstExpr(m: PSym, n: PNode; g: ModuleGraph): PNode =
  result = nil
  case n.kind
  of nkSym:
    var s = n.sym
    case s.kind
    of skEnumField:
      result = newIntNodeT(toInt128(s.position), n, g)
    of skConst:
      case s.magic
      of mIsMainModule: result = newIntNodeT(toInt128(ord(sfMainModule in m.flags)), n, g)
      of mCompileDate: result = newStrNodeT(getDateStr(), n, g)
      of mCompileTime: result = newStrNodeT(getClockStr(), n, g)
      of mCpuEndian: result = newIntNodeT(toInt128(ord(CPU[g.config.target.targetCPU].endian)), n, g)
      of mHostOS: result = newStrNodeT(toLowerAscii(platform.OS[g.config.target.targetOS].name), n, g)
      of mHostCPU: result = newStrNodeT(platform.CPU[g.config.target.targetCPU].name.toLowerAscii, n, g)
      of mBuildOS: result = newStrNodeT(toLowerAscii(platform.OS[g.config.target.hostOS].name), n, g)
      of mBuildCPU: result = newStrNodeT(platform.CPU[g.config.target.hostCPU].name.toLowerAscii, n, g)
      of mAppType: result = getAppType(n, g)
      of mIntDefine:
        if isDefined(g.config, s.name.s):
          try:
            result = newIntNodeT(toInt128(g.config.symbols[s.name.s].parseInt), n, g)
          except ValueError:
            localError(g.config, s.info,
              "{.intdefine.} const was set to an invalid integer: '" &
                g.config.symbols[s.name.s] & "'")
        else:
          result = copyTree(s.ast)
      of mStrDefine:
        if isDefined(g.config, s.name.s):
          result = newStrNodeT(g.config.symbols[s.name.s], n, g)
        else:
          result = copyTree(s.ast)
      of mBoolDefine:
        if isDefined(g.config, s.name.s):
          try:
            result = newIntNodeT(toInt128(g.config.symbols[s.name.s].parseBool.int), n, g)
          except ValueError:
            localError(g.config, s.info,
              "{.booldefine.} const was set to an invalid bool: '" &
                g.config.symbols[s.name.s] & "'")
        else:
          result = copyTree(s.ast)
      else:
        result = copyTree(s.ast)
    of skProc, skFunc, skMethod:
      result = n
    of skParam:
      if s.typ != nil and s.typ.kind == tyTypeDesc:
        result = newSymNodeTypeDesc(s, n.info)
    of skType:
      # XXX gensym'ed symbols can come here and cannot be resolved. This is
      # dirty, but correct.
      if s.typ != nil:
        result = newSymNodeTypeDesc(s, n.info)
    of skGenericParam:
      if s.typ.kind == tyStatic:
        if s.typ.n != nil and tfUnresolved notin s.typ.flags:
          result = s.typ.n
          result.typ = s.typ.base
      elif s.typ.isIntLit:
        result = s.typ.n
      else:
        result = newSymNodeTypeDesc(s, n.info)
    else: discard
  of nkCharLit..nkNilLit:
    result = copyNode(n)
  of nkIfExpr:
    result = getConstIfExpr(m, n, g)
  of nkCallKinds:
    if n[0].kind != nkSym: return
    var s = n[0].sym
    if s.kind != skProc and s.kind != skFunc: return
    try:
      case s.magic
      of mNone:
        # If it has no sideEffect, it should be evaluated. But not here.
        return
      of mLow:
        if skipTypes(n[1].typ, abstractVarRange).kind in tyFloat..tyFloat64:
          result = newFloatNodeT(firstFloat(n[1].typ), n, g)
        else:
          result = newIntNodeT(firstOrd(g.config, n[1].typ), n, g)
      of mHigh:
        if skipTypes(n[1].typ, abstractVar+{tyUserTypeClassInst}).kind notin
            {tySequence, tyString, tyCString, tyOpenArray, tyVarargs}:
          if skipTypes(n[1].typ, abstractVarRange).kind in tyFloat..tyFloat64:
            result = newFloatNodeT(lastFloat(n[1].typ), n, g)
          else:
            result = newIntNodeT(lastOrd(g.config, skipTypes(n[1].typ, abstractVar)), n, g)
        else:
          var a = getArrayConstr(m, n[1], g)
          if a.kind == nkBracket:
            # we can optimize it away:
            result = newIntNodeT(toInt128(a.len-1), n, g)
      of mLengthOpenArray:
        var a = getArrayConstr(m, n[1], g)
        if a.kind == nkBracket:
          # we can optimize it away! This fixes the bug ``len(134)``.
          result = newIntNodeT(toInt128(a.len), n, g)
        else:
          result = magicCall(m, n, g)
      of mLengthArray:
        # It doesn't matter if the argument is const or not for mLengthArray.
        # This fixes bug #544.
        result = newIntNodeT(lengthOrd(g.config, n[1].typ), n, g)
      of mSizeOf:
        result = foldSizeOf(g.config, n, nil)
      of mAlignOf:
        result = foldAlignOf(g.config, n, nil)
      of mOffsetOf:
        result = foldOffsetOf(g.config, n, nil)
      of mAstToStr:
        result = newStrNodeT(renderTree(n[1], {renderNoComments}), n, g)
      of mConStrStr:
        result = foldConStrStr(m, n, g)
      of mIs:
        # The only kind of mIs node that comes here is one depending on some
        # generic parameter and that's (hopefully) handled at instantiation time
        discard
      else:
        result = magicCall(m, n, g)
    except OverflowDefect:
      localError(g.config, n.info, "over- or underflow")
    except DivByZeroDefect:
      localError(g.config, n.info, "division by zero")
  of nkAddr:
    var a = getConstExpr(m, n[0], g)
    if a != nil:
      result = n
      n[0] = a
  of nkBracket, nkCurly:
    result = copyNode(n)
    for i, son in n.pairs:
      var a = getConstExpr(m, son, g)
      if a == nil: return nil
      result.add a
    incl(result.flags, nfAllConst)
  of nkRange:
    var a = getConstExpr(m, n[0], g)
    if a == nil: return
    var b = getConstExpr(m, n[1], g)
    if b == nil: return
    result = copyNode(n)
    result.add a
    result.add b
  #of nkObjConstr:
  #  result = copyTree(n)
  #  for i in 1..<n.len:
  #    var a = getConstExpr(m, n[i][1])
  #    if a == nil: return nil
  #    result[i][1] = a
  #  incl(result.flags, nfAllConst)
  of nkPar, nkTupleConstr:
    # tuple constructor
    result = copyNode(n)
    if (n.len > 0) and (n[0].kind == nkExprColonExpr):
      for i, expr in n.pairs:
        let exprNew = copyNode(expr) # nkExprColonExpr
        exprNew.add expr[0]
        let a = getConstExpr(m, expr[1], g)
        if a == nil: return nil
        exprNew.add a
        result.add exprNew
    else:
      for i, expr in n.pairs:
        let a = getConstExpr(m, expr, g)
        if a == nil: return nil
        result.add a
    incl(result.flags, nfAllConst)
  of nkChckRangeF, nkChckRange64, nkChckRange:
    var a = getConstExpr(m, n[0], g)
    if a == nil: return
    if leValueConv(n[1], a) and leValueConv(a, n[2]):
      result = a              # a <= x and x <= b
      result.typ = n.typ
    else:
      localError(g.config, n.info,
        "conversion from $1 to $2 is invalid" %
          [typeToString(n[0].typ), typeToString(n.typ)])
  of nkStringToCString, nkCStringToString:
    var a = getConstExpr(m, n[0], g)
    if a == nil: return
    result = a
    result.typ = n.typ
  of nkHiddenStdConv, nkHiddenSubConv, nkConv:
    var a = getConstExpr(m, n[1], g)
    if a == nil: return
    result = foldConv(n, a, g, check=true)
  of nkCast:
    var a = getConstExpr(m, n[1], g)
    if a == nil: return
    if n.typ != nil and n.typ.kind in NilableTypes:
      # we allow compile-time 'cast' for pointer types:
      result = a
      result.typ = n.typ
  of nkBracketExpr: result = foldArrayAccess(m, n, g)
  of nkDotExpr: result = foldFieldAccess(m, n, g)
  of nkCheckedFieldExpr:
    assert n[0].kind == nkDotExpr
    result = foldFieldAccess(m, n[0], g)
  of nkStmtListExpr:
    var i = 0
    while i <= n.len - 2:
      if n[i].kind in {nkComesFrom, nkCommentStmt, nkEmpty}: i.inc
      else: break
    if i == n.len - 1:
      result = getConstExpr(m, n[i], g)
  else:
    discard
