#!/System/Library/Frameworks/Ruby.framework/Versions/Current/usr/bin/ruby
# This script installs to /usr/local only. To install elsewhere you can just
# untar https://github.com/Homebrew/brew/tarball/master anywhere you like or
# change the value of HOMEBREW_PREFIX.
HOMEBREW_PREFIX = "/usr/local".freeze
HOMEBREW_CACHE = "#{ENV["HOME"]}/Library/Caches/Homebrew".freeze
BREW_REPO = "https://github.com/Homebrew/brew".freeze
CORE_TAP_REPO = "https://github.com/Homebrew/homebrew-core".freeze

# no analytics during installation
ENV["HOMEBREW_NO_ANALYTICS_THIS_RUN"] = "1"

module Tty extend self
  def blue; bold 34; end
  def white; bold 39; end
  def red; underline 31; end
  def reset; escape 0; end
  def bold n; escape "1;#{n}" end
  def underline n; escape "4;#{n}" end
  def escape n; "\033[#{n}m" if STDOUT.tty? end
end

class Array
  def shell_s
    cp = dup
    first = cp.shift
    cp.map{ |arg| arg.gsub " ", "\\ " }.unshift(first) * " "
  end
end

def ohai *args
  puts "#{Tty.blue}==>#{Tty.white} #{args.shell_s}#{Tty.reset}"
end

def warn warning
  puts "#{Tty.red}Warning#{Tty.reset}: #{warning.chomp}"
end

def system *args
  abort "Failed during: #{args.shell_s}" unless Kernel.system(*args)
end

def sudo *args
  ohai "/usr/bin/sudo", *args
  system "/usr/bin/sudo", *args
end

def getc  # NOTE only tested on OS X
  system "/bin/stty raw -echo"
  if STDIN.respond_to?(:getbyte)
    STDIN.getbyte
  else
    STDIN.getc
  end
ensure
  system "/bin/stty -raw echo"
end

class Version
  include Comparable
  attr_reader :parts

  def initialize(str)
    @parts = str.split(".").map { |i| i.to_i }
  end

  def <=>(other)
    parts <=> self.class.new(other).parts
  end
end

def macos_version
  @macos_version ||= Version.new(`/usr/bin/sw_vers -productVersion`.chomp[/10\.\d+/])
end

def should_install_command_line_tools?
  return false if macos_version < "10.9"
  developer_dir = `/usr/bin/xcode-select -print-path 2>/dev/null`.chomp
  developer_dir.empty? || !File.exist?("#{developer_dir}/usr/bin/git")
end

def git
  @git ||= if ENV['GIT'] and File.executable? ENV['GIT']
    ENV['GIT']
  elsif Kernel.system '/usr/bin/which -s git'
    'git'
  else
    exe = `xcrun -find git 2>/dev/null`.chomp
    exe if $? && $?.success? && !exe.empty? && File.executable?(exe)
  end

  return unless @git
  # Github only supports HTTPS fetches on 1.7.10 or later:
  # https://help.github.com/articles/https-cloning-errors
  `#{@git} --version` =~ /git version (\d\.\d+\.\d+)/
  return if $1.nil? or Version.new($1) < "1.7.10"

  @git
end

def chmod?(d)
  File.directory?(d) && !(File.readable?(d) && File.writable?(d) && File.executable?(d))
end

def chown?(d)
  !File.owned?(d)
end

def chgrp?(d)
  !File.grpowned?(d)
end

# Invalidate sudo timestamp before exiting
at_exit { Kernel.system "/usr/bin/sudo", "-k" }

# The block form of Dir.chdir fails later if Dir.CWD doesn't exist which I
# guess is fair enough. Also sudo prints a warning message for no good reason
Dir.chdir "/usr"

####################################################################### script
abort "See Linuxbrew: http://linuxbrew.sh/" if /linux/i === RUBY_PLATFORM
abort "MacOS too old, see: https://github.com/mistydemeo/tigerbrew" if macos_version < "10.6"
abort "Don't run this as root!" if Process.uid == 0
abort <<-EOABORT unless `dsmemberutil checkmembership -U "#{ENV['USER']}" -G admin`.include? "user is a member"
This script requires the user #{ENV['USER']} to be an Administrator. If this
sucks for you then you can install Homebrew in your home directory or however
you please; please refer to our homepage. If you still want to use this script
set your user to be an Administrator in System Preferences or `su' to a
non-root user with Administrator privileges.
EOABORT
contents = Dir.glob(HOMEBREW_PREFIX+"*/{*,.git*}").join(" ").gsub!(%r{#{HOMEBREW_PREFIX}/}, "")
abort <<-EOABORT unless Dir["#{HOMEBREW_PREFIX}/.git/*"].empty?
It appears Homebrew is already installed. If your intent is to reinstall you
should do the following before running this installer again:
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall)"
The current contents of #{HOMEBREW_PREFIX} are #{contents}
EOABORT
# Tests will fail if the prefix exists, but we don't have execution
# permissions. Abort in this case.
abort <<-EOABORT if File.directory? HOMEBREW_PREFIX and not File.executable? HOMEBREW_PREFIX
The Homebrew prefix, #{HOMEBREW_PREFIX}, exists but is not searchable. If this is
not intentional, please restore the default permissions and try running the
installer again:
    sudo chmod 775 #{HOMEBREW_PREFIX}
EOABORT

ohai "This script will install:"
puts "#{HOMEBREW_PREFIX}/bin/brew"
puts "#{HOMEBREW_PREFIX}/Library/..."
puts "#{HOMEBREW_PREFIX}/share/doc/homebrew"
puts "#{HOMEBREW_PREFIX}/share/man/man1/brew.1"
puts "#{HOMEBREW_PREFIX}/share/zsh/site-functions/_brew"
puts "#{HOMEBREW_PREFIX}/etc/bash_completion.d/brew"

chmods = %w( . bin etc etc/bash_completion.d include lib lib/pkgconfig Library sbin share var var/log share/locale share/man
             share/man/man1 share/man/man2 share/man/man3 share/man/man4
             share/man/man5 share/man/man6 share/man/man7 share/man/man8
             share/info share/doc share/aclocal share/zsh share/zsh/site-functions ).
             map { |d| File.join(HOMEBREW_PREFIX, d) }.select { |d| chmod?(d) }
chowns = chmods.select { |d| chown?(d) }
chgrps = chmods.select { |d| chgrp?(d) }

unless chmods.empty?
  ohai "The following directories will be made group writable:"
  puts(*chmods)
end
unless chowns.empty?
  ohai "The following directories will have their owner set to #{Tty.underline 39}#{ENV['USER']}#{Tty.reset}:"
  puts(*chowns)
end
unless chgrps.empty?
  ohai "The following directories will have their group set to #{Tty.underline 39}admin#{Tty.reset}:"
  puts(*chgrps)
end

if File.directory? HOMEBREW_PREFIX
  sudo "/bin/chmod", "g+rwx", *chmods unless chmods.empty?
  sudo "/usr/sbin/chown", ENV['USER'], *chowns unless chowns.empty?
  sudo "/usr/bin/chgrp", "admin", *chgrps unless chgrps.empty?
else
  sudo "/bin/mkdir", "-p", HOMEBREW_PREFIX
  sudo "/bin/chmod", "g+rwx", HOMEBREW_PREFIX
  # the group is set to wheel by default for some reason
  sudo "/usr/sbin/chown", "#{ENV['USER']}:admin", HOMEBREW_PREFIX
end

sudo "/bin/mkdir", "-p", HOMEBREW_CACHE unless File.directory? HOMEBREW_CACHE
sudo "/bin/chmod", "g+rwx", HOMEBREW_CACHE if chmod? HOMEBREW_CACHE
sudo "/usr/sbin/chown", ENV['USER'], HOMEBREW_CACHE if chown? HOMEBREW_CACHE
sudo "/usr/bin/chgrp", "admin", HOMEBREW_CACHE if chgrp? HOMEBREW_CACHE

if should_install_command_line_tools?
  ohai "Searching online for the Command Line Tools"
  # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
  clt_placeholder = "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  sudo "/usr/bin/touch", clt_placeholder
  clt_label = `softwareupdate -l | grep -B 1 -E "Command Line (Developer|Tools)" | awk -F"*" '/^ +\\*/ {print $2}' | sed 's/^ *//' | head -n1`.chomp
  ohai "Installing #{clt_label}"
  sudo "/usr/sbin/softwareupdate", "-i", clt_label
  sudo "/bin/rm", "-f", clt_placeholder
  sudo "/usr/bin/xcode-select", "--switch", "/Library/Developer/CommandLineTools"
end

# Headless install may have failed, so fallback to original 'xcode-select' method
if should_install_command_line_tools?
  if STDIN.tty?
    ohai "Installing the Command Line Tools (expect a GUI popup):"
    sudo "/usr/bin/xcode-select", "--install"
    puts "Press any key when the installation has completed."
    getc
    sudo "/usr/bin/xcode-select", "--switch", "/Library/Developer/CommandLineTools"
  else
    abort "Error: Cannot proceed with manual Command Line Tools install without user input!"
  end
end

abort <<-EOABORT if `/usr/bin/xcrun clang 2>&1` =~ /license/ && !$?.success?
You have not agreed to the Xcode license.
Before running the installer again please agree to the license by opening
Xcode.app or running:
    sudo xcodebuild -license
EOABORT

ohai "Downloading and installing Homebrew..."
Dir.chdir HOMEBREW_PREFIX do
  if git
    # we do it in four steps to avoid merge errors when reinstalling
    system git, "init", "-q"

    # "git remote add" will fail if the remote is defined in the global config
    system git, "config", "remote.origin.url", BREW_REPO
    system git, "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"

    # ensure we don't munge line endings on checkout
    system git, "config", "core.autocrlf", "false"

    args = git, "fetch", "origin", "master:refs/remotes/origin/master", "-n"
    args << "--depth=1" unless ARGV.include?("--full") || !ENV["HOMEBREW_DEVELOPER"].nil?
    system(*args)

    system git, "reset", "--hard", "origin/master"

    system "#{HOMEBREW_PREFIX}/bin/brew", "tap", "homebrew/core"
  else
    # -m to stop tar erroring out if it can't modify the mtime for root owned directories
    # pipefail to cause the exit status from curl to propagate if it fails
    curl_flags = "fsSL"
    core_tap = "#{HOMEBREW_PREFIX}/Library/Taps/homebrew/homebrew-core"
    system "/bin/bash -o pipefail -c '/usr/bin/curl -#{curl_flags} #{BREW_REPO}/tarball/master | /usr/bin/tar xz -m --strip 1'"

    system "/bin/mkdir", "-p", core_tap
    Dir.chdir core_tap do
      system "/bin/bash -o pipefail -c '/usr/bin/curl -#{curl_flags} #{CORE_TAP_REPO}/tarball/master | /usr/bin/tar xz -m --strip 1'"
    end
  end
end

warn "#{HOMEBREW_PREFIX}/bin is not in your PATH." unless ENV['PATH'].split(':').include? "#{HOMEBREW_PREFIX}/bin"

ohai "Installation successful!"
ohai "Next steps"

if macos_version < "10.9" and macos_version > "10.6"
  `/usr/bin/cc --version 2> /dev/null` =~ %r[clang-(\d{2,})]
  version = $1.to_i
  puts "Install the #{Tty.white}Command Line Tools for Xcode#{Tty.reset}: https://developer.apple.com/downloads" if version < 425
else
  puts "Install #{Tty.white}Xcode#{Tty.reset}: https://developer.apple.com/xcode" unless File.exist? "/usr/bin/cc"
end

puts "Run `brew help` to get started"
puts "Further documentation: https://git.io/brew-docs"
ohai "Homebrew has enabled anonymous aggregate user behaviour analytics"
puts "Read the analytics documentation (and how to opt-out) here:"
puts "  https://git.io/brew-analytics"
if git
  Dir.chdir HOMEBREW_PREFIX do
    system git, "config", "--local", "--replace-all", "homebrew.analyticsmessage", "true"
  end
end
