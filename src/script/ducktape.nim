import duktape/js

# Define proc to be bound
var println: DTCFunction = (proc (ctx: DTContext): cint{.stdcall.} =
    echo duk_to_string(ctx, 0)
)

# Create duktape context
var ctx = duk_create_heap_default()

# Bind proc to the context and global "println" variable 
var err = ctx.duk_push_c_function( println, cast[cint](-1))
var r = ctx.duk_put_global_string("println")


# interpret Javascript expression
ctx.duk_eval_string( "1+20");
# Retreive value of last expression as an int
assert ctx.duk_get_int(-1) == 21

# interpret Javascript expression
ctx.duk_eval_string( "'foo'+'bar'+1");
# Call bound proc from Javascript
ctx.duk_eval_string( "println('foobar'+2)");

# Retreive value of last expression as a string
assert ctx.duk_get_string(-1) == "foobar1"

# Cleanup duktape memory
ctx.duk_destroy_heap();



const __context = {
  a: 1,
  b: 2,
  c: 3,
  d: {
    e: 4,
    f: 5,
    g: {
      h: 6,
      i: 7,
    },
  },
};

const  get = (target, prop) => {
  console.log("get", target, prop);

  let internal_context = __context;
  for( const part in target.prefix){
    console.log("internal_context", internal_context);
    console.log("part", part);
    console.log("internal_context[part]", internal_context[part]);
    internal_context = internal_context[part];
  }

  console.log("internal_context", internal_context);

  if(typeof internal_context[prop] == "object"){
    return new Proxy({ prefix: target.prefix.concat( prop ) }, {
      get: get,
    });
  }
}

const context = new Proxy({ prefix: [] }, {
  get: get,
});

console.log( context.d.g.h );
