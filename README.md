# ***Moved to [gitlab](https://gitlab.com/dcmorse/Heroku-Package-Builder-Buildpack)***
## Heroku Package Builder Buildpack
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
#### _IMPORTANT_ <br>If your package name contains dashes "-" replace them with double-underscores "\_\_" e.g. man-db -> man\_\_db
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
__*PACKAGE_BUILDER_BUILDFAIL*__ (1 or 0)<br>
Fail the whole build if a single package fails to install

__*PACKAGE_BUILDER_HOMEBREW_VERBOSE*__ (1 or 0)<br>
If =1, print all make output to build log

__*PACKAGE_BUILDER_INSTALL_QUIET*__ (1 or 0)<br>
Remove excessive install output

__*PACKAGE_BUILDER_REINSTALL_LINUXBREW*__ (1 or 0)<br>
Removes all packages installed before and starts anew

__*PACKAGE_BUILDER_MAX_BUILDTIME*__ (time in minutes)<br>
Max time to take building (not exact)

__*BUILD_DEBUG*__ (1 or 0)<br>
Print extra stuff when building

__*PACKAGE_BUILDER_NOINSTALL_GAWK*__ (1 or 0)<br>
__*PACKAGE_BUILDER_NOINSTALL_GCC*__ (1 or 0)<br>
~~__*PACKAGE_BUILDER_NOINSTALL_RUBY*__~~ (1 or 0)<br>
~~__*PACKAGE_BUILDER_NOINSTALL_PERL*__~~ (1 or 0)<br>
~~__*PACKAGE_BUILDER_NOINSTALL_PYTHON*__~~ (1 or 0)<br>
__*PACKAGE_BUILDER_NOINSTALL_DEFAULTS*__ (1 or 0)<br>
Some core tools are automatically installed on first install. Setting this to 1 disables this. PACKAGE_BUILDER_NOINSTALL_DEFAULTS=1 disables all automatic installs.

__*USE_DPKG_BUILDFLAGS*__ (1 or 0)<br>
Use the default buildflags as dpkg (on by default)

OVERVIEW
========
This buildpack allows you to install any software. At the moment it uses Linuxbrew exclusively, so if you want to install a non-Linuxbrew package you'll need to write a formula (read more [here](https://github.com/Homebrew/brew/blob/master/docs/Formula-Cookbook.md)).

Aside from simply running `brew install <package>` this buildpack aims to deal witht he unique constraints of Heroku, including the ~15 minute timeout and the max slug size limit (thsi part's in development).

If a package doesn't install, check the build log. Important messages will print to the log regardless, but diagnosis may require you setting BUILD_DEBUG=1. Note that you *could* enable xtrace to the result of absolutely every command run by setting BUILDPACK_XTRACE=1, but it would print so much that something might break. So it's not recommended.

Lastly, if you think I messed something up or you think that *everything* is just *perfect* then please let me know by opening an issue.

NOTES
=====
1. If the build process times out before all packages are installed, reduce the number of packages in `package-extras.yaml` until you have a successful build. Then on the next build replace the successful packages with the removed packages. The successfully installed packages should still be available.
2. If you can't even get one package to build, have a look in the build log and see what its dependencies are. Try installing those individually before the main package, following the pattern in (1).
3. This package mostly depends on [Linuxbrew](https://github.com/Linuxbrew/brew), which is a fork of  [Homebrew](https://github.com/Homebrew/brew), which collects some anonymized info about your usage. To disable this set the config var `HOMEBREW_NO_ANALYTICS` to `1`.

TODO
====
- test having formulas in the project root
- check on the slug size before installing more packages
- install multiple packages simultaneously
- make better yaml parser
- make json parser
