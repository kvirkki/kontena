name "kontena-cli"
license "Apache 2.0"
default_version File.read('../VERSION').strip
source path: ".."
dependency "ruby"
dependency "rubygems"
dependency "libxml2"
dependency "libxslt"
build do
  gem "build --verbose kontena-cli.gemspec"
  gem "install rb-readline -v 0.5.4 --no-ri --no-doc"
  gem "install nokogiri -v 1.6.8 --no-ri --no-doc"
  gem "install --local ./kontena-cli-#{default_version}.gem --no-ri --no-doc"
  copy "omnibus/wrapper-scripts/kontena", "#{install_dir}/bin/kontena"
end
