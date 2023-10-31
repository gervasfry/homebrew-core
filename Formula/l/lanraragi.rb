require "language/node"

class Lanraragi < Formula
  desc "Web application for archival and reading of manga/doujinshi"
  homepage "https://github.com/Difegue/LANraragi"
  license "MIT"
  head "https://github.com/Difegue/LANraragi.git", branch: "dev"

  stable do
    url "https://github.com/Difegue/LANraragi/archive/refs/tags/v.0.9.0.tar.gz"
    sha256 "76390a12c049216c708b522372a7eed9f2fcf8f8d462af107d881dbb1ce3a79f"

    # patch for `Can't load application from file ".../lanraragi": Can't open file "oshino"`
    # remove in next release
    patch do
      url "https://github.com/Difegue/LANraragi/commit/d2ab6807cc4b1ed1fe902c264cba7750ae07f435.patch?full_index=1"
      sha256 "3edc8e1248e5931bfc7f983af93b92354bb85368582d4ccedcd1af93013ce24a"
    end
  end

  bottle do
    sha256 cellar: :any,                 arm64_sonoma:   "6d7cecbd0f38afed3ee880deca03e8aee23cc18f4d7fb51657d0a0e8e9bd80b6"
    sha256 cellar: :any,                 arm64_ventura:  "6ac4aa61abe98f69a42b73b465e8928fa7c06d3933f023fddc2690ad588af4d5"
    sha256 cellar: :any,                 arm64_monterey: "aec9003288a39616f378a570a1e13b26dc299061f2f436e0d83b18365dd6cc9f"
    sha256 cellar: :any,                 sonoma:         "6c1d39363d02694aa3ad570371eef0a7866974629d0cda89edbd1fdea93b9607"
    sha256 cellar: :any,                 ventura:        "2c8e3c4d10539a00006d61e1dd76c8263fcb91cf51d071e356c250117889cdf2"
    sha256 cellar: :any,                 monterey:       "708cdbb45a1da8b23ca91564568ec0b451b10911f2b4ff70d1a66d37e69e14d9"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "5e9a46d6556104ff0c6039b1fee385acaa23a344a095bd956d8816c1cfad267c"
  end

  depends_on "nettle" => :build
  depends_on "pkg-config" => :build
  depends_on "cpanminus"
  depends_on "ghostscript"
  depends_on "giflib"
  depends_on "imagemagick"
  depends_on "jpeg-turbo"
  depends_on "libpng"
  depends_on "node"
  depends_on "openssl@3"
  depends_on "perl"
  depends_on "redis"
  depends_on "zstd"

  uses_from_macos "libarchive"

  resource "libarchive-headers" do
    on_macos do
      url "https://github.com/apple-oss-distributions/libarchive/archive/refs/tags/libarchive-121.tar.gz"
      sha256 "f38736ffdbf9005726bdc126e68ff34ddaee25326ae51d58e4385de717bc773f"
    end
  end

  resource "Image::Magick" do
    url "https://cpan.metacpan.org/authors/id/J/JC/JCRISTY/Image-Magick-7.1.1-20.tar.gz"
    sha256 "a0c0305d0071b95d8580f1c18548beb683453d59d12cd8d9a9d3f6abe922ea38"
  end

  def install
    ENV.prepend_create_path "PERL5LIB", "#{libexec}/lib/perl5"
    ENV.prepend_path "PERL5LIB", "#{libexec}/lib"

    # On Linux, use the headers provided by the libarchive formula rather than the ones provided by Apple.
    ENV["CFLAGS"] = if OS.mac?
      "-I#{libexec}/include"
    else
      "-I#{Formula["libarchive"].opt_include}"
    end

    ENV["OPENSSL_PREFIX"] = Formula["openssl@3"].opt_prefix

    imagemagick = Formula["imagemagick"]
    resource("Image::Magick").stage do
      inreplace "Makefile.PL" do |s|
        s.gsub! "/usr/local/include/ImageMagick-#{imagemagick.version.major}",
                "#{imagemagick.opt_include}/ImageMagick-#{imagemagick.version.major}"
      end

      system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}"
      system "make"
      system "make", "install"
    end

    if OS.mac?
      resource("libarchive-headers").stage do
        cd "libarchive/libarchive" do
          (libexec/"include").install "archive.h", "archive_entry.h"
        end
      end
    end

    system "cpanm", "Config::AutoConf", "--notest", "-l", libexec
    system "npm", "install", *Language::Node.local_npm_install_args
    system "perl", "./tools/install.pl", "install-full"

    prefix.install "README.md"
    (libexec/"lib").install Dir["lib/*"]
    libexec.install "script", "package.json", "public", "templates", "tests", "lrr.conf"
    cd "tools/build/homebrew" do
      bin.install "lanraragi"
      libexec.install "redis.conf"
    end
  end

  def caveats
    <<~EOS
      Automatic thumbnail generation will not work properly on macOS < 10.15 due to the bundled Libarchive being too old.
      Opening archives for reading will generate thumbnails normally.
    EOS
  end

  test do
    # Make sure lanraragi writes files to a path allowed by the sandbox
    ENV["LRR_LOG_DIRECTORY"] = ENV["LRR_TEMP_DIRECTORY"] = testpath
    %w[server.pid shinobu.pid minion.pid].each { |file| touch file }

    # Set PERL5LIB as we're not calling the launcher script
    ENV["PERL5LIB"] = libexec/"lib/perl5"
    pid = fork do
      exec "npm start --prefix #{libexec}"
    end
    sleep 2

    assert_match "LANraragi 0.9.0 started. (Production Mode)", (testpath/"lanraragi.log").read
    assert_match "Shinobu File Watcher started", (testpath/"shinobu.log").read
  ensure
    Process.kill("TERM", pid)
    Process.wait(pid)
  end
end
