## bugfix/core

* Fixed the fact that using of invalid listen address made
  tarantool blind. Now in case of invalid listen address
  tarantool still listen old one (gh-6092).