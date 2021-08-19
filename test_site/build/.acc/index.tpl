<!doctype html>
<html class="no-js" lang="">

<head>
  <meta charset="utf-8">
  <title>{{ pages.index.title }}</title>
  <meta name="description" content="">
  <meta name="viewport" content="width=device-width, initial-scale=1">

  {% for title, content in pages.index.meta %}
  <meta property="{{ title }}" content="{{ content }}">
  {% endfor %}


  <link rel="manifest" href="site.webmanifest">
  <link rel="apple-touch-icon" href="icon.png">
  <!-- Place favicon.ico in the root directory -->

  <link rel="stylesheet" href="css/normalize.css">
  <link rel="stylesheet" href="css/style.css">

  <meta name="theme-color" content="#fafafa">
</head>

<body>
  <section class="hero">
    <h1 class="hero__title">{{ pages.index.sections.hero.title }}</h1>
    <p class="hero__text">{{ pages.index.sections.hero.text }}</p>
  </section>
  <main>
    {{ pages.index.sections.main | safe }}
    <picture>
      <source type="image/svg+xml" srcset="pyramid.svg">
      <source type="image/webp" srcset="pyramid.webp">
      <img src="pyramid.png" alt="regular pyramid built from four equilateral triangles">
    </picture>
  </main>
  <footer class="footer">
    <span class="footer__copyright">{{ pages.index.footer.copyright }}</span>
    <a href="{{ pages.index.footer.link.href }}"><span class="footer__link">{{ pages.index.footer.link.text }}</span>
  </footer>

  <script src="js/vendor/modernizr-3.11.4.min.js"></script>
  <script src="js/app.js"></script>

  <!-- Google Analytics: change UA-XXXXX-Y to be your site's ID. -->
  <script>
    window.ga = function () { ga.q.push(arguments) }; ga.q = []; ga.l = +new Date;
    ga('create', 'UA-XXXXX-Y', 'auto'); ga('set', 'anonymizeIp', true); ga('set', 'transport', 'beacon'); ga('send', 'pageview')
  </script>
  <script src="https://www.google-analytics.com/analytics.js" async></script>
</body>

</html>
