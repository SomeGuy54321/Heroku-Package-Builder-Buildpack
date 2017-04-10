# Heroku Package Builder Buildpack
### Install extra packages in your Heroku dyno without root

This buildpack mostly uses [Linuxbrew](https://github.com/Linuxbrew/brew).

Use this by finding the package you want [here](http://brewformulas.org/search?utf8=%E2%9C%93&search%5Bterm%5D=&commit=Search) and placing them in `package-extras.yaml` in the root of your git repo like so:
```
packages:
  - postgresql
  - man__db
  - openssh
uninstall:
  - gnutls
reinstall:
  - xz
formulas:
  man-db: https://raw.githubusercontent.com/Linuxbrew/homebrew-extra/master/Formula/man-db.rb
options:
  openssh: 
    - with-ldns
    - with-libressl
config:
  postgresql:
    - setup_djangodb.sh
```
YAML Setup
==========
#### _IMPORTANT_ <br>If your package name contains dashes "-" replace them with double-underscores "__" e.g. man-db -> man__db
##### install
- just the package name
- installed in the order entered
- runs first
#### reinstall
- reinstall something
- runs second
#### uninstall
- OPTIONAL
- uninstall something
- runs third
##### formulas
- OPTIONAL
- a custom linuxbrew formula to apply to a package
- if your build fails, try:
  - Remove this package from `package-extras.yaml`
  - Get a successful build
  - Run `heroku run brew search <packagename> -a <appname>`
  - If it has a special path like `.linuxbrew/dupes/<packagename>` then add this to your `formulas` section for this package
  - the key must correspond to an install/uninstall/reinstall package
- Some Linux-specific formulas can be found [here](https://github.com/Linuxbrew/homebrew-extra)
##### options
- OPTIONAL
- Command line flags to use when building the package
- e.g. the above example builds openssh with ldns support and LibreSSL and translates to `brew install homebrew/dupes/openssh --with-ldns --with-libressl` on the command line
##### config
- OPTIONAL
- Runs the named scripts from your $HOME directory after installing the package
  - make sure the script has a shebang line
- The script will be passed the same arguments as the compile script
  - See [bin/compile](https://devcenter.heroku.com/articles/buildpack-api#bin-compile) in the Heroku Buildpack API documentation

CONFIG VARS
===========
__*PACKAGE_BUILDER_NOBUILDFAIL*__ (1 or 0)<br>
Do not fail the whole build if a single package fails to install

__*PACKAGE_BUILDER_HOMEBREW_VERBOSE*__ (1 or 0)<br>
If =1, print all make output to build log

__*PACKAGE_BUILDER_INSTALL_QUIET*__ (1 or 0)<br>
Remove excessive install output

__*PACKAGE_BUILDER_REINSTALL_LINUXBREW*__ (1 or 0)<br>
Removes all packages installed before and starts anew

__*PACKAGE_BUILDER_MAX_BUILDTIME*__ (time in minutes)<br>
Max time to take building (not exact)

__*PACKAGE_BUILDER_NOINSTALL_GAWK*__ (1 or 0)<br>
__*PACKAGE_BUILDER_NOINSTALL_GCC*__ (1 or 0)<br>
~~__*PACKAGE_BUILDER_NOINSTALL_RUBY*__~~ (1 or 0)<br>
~~__*PACKAGE_BUILDER_NOINSTALL_PERL*__~~ (1 or 0)<br>
~~__*PACKAGE_BUILDER_NOINSTALL_PYTHON*__~~ (1 or 0)<br>
~~__*PACKAGE_BUILDER_NOINSTALL_DEFAULTS*__~~ (1 or 0)<br>
Some core tools are automatically installed on first install. Setting this to 1 disables this. PACKAGE_BUILDER_NOINSTALL_DEFAULTS=1 disables all automatic installs.
__*USE_DPKG_BUILDFLAGS*__ (1 or 0)<br>
Use the default buildflags as dpkg (on by default)

NOTES
====
1. If the build process times out before all packages are installed, reduce the number of packages in `package-extras.yaml` until you have a successful build. Then on the next build replace the successful packages with the removed packages. The successfully installed packages should still be available.
2. If you can't even get one package to build, have a look in the build log and see what its dependencies are. Try installing those individually before the main package, following the pattern in (1).
3. This package mostly depends on [Linuxbrew](https://github.com/Linuxbrew/brew), which is a fork of  [Homebrew](https://github.com/Homebrew/brew), which collects some anonymized info about your usage. To disable this set the config var `HOMEBREW_NO_ANALYTICS` to `1`.

TODO
====
- build stuff without relying on linuxbrew
- smart compression selecting
- smart job number selecting
- make better yaml parser
- make json parser
