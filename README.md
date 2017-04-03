# Heroku Package Builder Buildpack
### Install extra packages in your Heroku dyno without root

This buildpack mostly uses [Linuxbrew](https://github.com/Linuxbrew/brew).

Use this by finding the package you want [here](http://brewformulas.org/search?utf8=%E2%9C%93&search%5Bterm%5D=&commit=Search) and placing them in `package-extras.yaml` in your root directory like so:
```
packages:
  - postgresql
  - strace
  - linux-pam
  - openssh
formulas:
  strace: https://github.com/Linuxbrew/homebrew-extra/blob/master/Formula/strace.rb
  linux-pam: linuxbrew/extra/linux-pam
  openssh: homebrew/dupes/openssh
options:
  openssh: 
    - with-ldns
    - with-libressl
config:
  postgresql:
    - setup_djangodb.sh
uninstall:
  - gnutls
```
YAML Setup
==========
##### packages
- REQUIRED
- just the package name
- installed in the order entered
##### formulas
- OPTIONAL
- a custom linuxbrew formula to apply to a package
- if your build fails, try:
  - Remove this package from `package-extras.yaml`
  - Get a successful build
  - Run `heroku run brew search <packagename> -a <appname>`
  - If it has a special path like `homebrew/dupes/<packagename>` then add this to your `formulas` section for this package
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
#### uninstall
- OPTIONAL
- uninstall something

CONFIG VARS
===========
*PACKAGE_BUILDER_NOBUILDFAIL* (1 or 0) - do not fail the whole build if a single package fails to install
*PACKAGE_BUILDER_HOMEBREW_VERBOSE* (1 or 0) - if =1, print all make output to build log
*PACKAGE_BUILDER_INSTALL_QUIET* (1 or 0) - remove excessive install output

NOTES
====
1. If the build process times out before all packages are installed, reduce the number of packages in `package-extras.yaml` until you have a successful build. Then on the next build replace the successful packages with the removed packages. The successfully installed packages should still be available.
2. If you can't even get one package to build, have a look in the build log and see what its dependencies are. Try installing those individually before the main package, following the pattern in (1).
3. This package mostly depends on [Linuxbrew](https://github.com/Linuxbrew/brew), which is a fork of  [Homebrew](https://github.com/Homebrew/brew), which collects some anonymized info about your usage. To disable this set the config var `HOMEBREW_NO_ANALYTICS` to `1`.

TODO
====
- build stuff without relying on linuxbrew
- better error handling
- allow easier adjustment of build time
  - easily set buildflags so less time is spent compiling
  - find perfect jobs number so there aren't forking issues and its fast
