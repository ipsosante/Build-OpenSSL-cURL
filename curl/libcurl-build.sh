#!/bin/bash

# This script downlaods and builds the Mac, iOS and tvOS libcurl libraries with Bitcode enabled

# Credits:
#
# Felix Schwarz, IOSPIRIT GmbH, @@felix_schwarz.
#   https://gist.github.com/c61c0f7d9ab60f53ebb0.git
# Bochun Bai
#   https://github.com/sinofool/build-libcurl-ios
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL 
# Preston Jennings
#   https://github.com/prestonj/Build-OpenSSL-cURL 



####################################################
IPHONEOS_DEPLOYMENT_TARGET="11.0"
OPENSSL="${PWD}/../openssl"  
####################################################

set -e

# set trap to help debug any build errors
trap 'echo "** ERROR with Build - Check /tmp/curl*.log"; tail /tmp/curl*.log' INT TERM EXIT

usage ()
{
	echo "usage: $0 [curl version]" 
	trap - INT TERM EXIT
	exit 127
}

if [ "$1" == "-h" ]; then
	usage
fi

if [ -z $1 ]; then
	CURL_VERSION="curl-7.59.0"
else
	CURL_VERSION="curl-$1"
fi


# HTTP2 support
NOHTTP2="/tmp/no-http2"
if [ ! -f "$NOHTTP2" ]; then
	# nghttp2 will be in ../nghttp2/{Platform}/{arch}
	NGHTTP2="${PWD}/../nghttp2"  
fi

if [ ! -z "$NGHTTP2" ]; then 
	echo "Building with HTTP2 Support (nghttp2)"
else
	echo "Building without HTTP2 Support (nghttp2)"
	NGHTTP2CFG=""
	NGHTTP2LIB=""
fi

buildMac()
{
	ARCH=$1
	HOST=$2

	echo "Building ${CURL_VERSION} for ${ARCH}"

	if [ ! -z "$NGHTTP2" ]; then 
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/Mac/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/Mac/${ARCH}/lib"
	fi
	
	export CC="${BUILD_TOOLS}/usr/bin/clang"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -L${OPENSSL}/Mac/lib ${NGHTTP2LIB}"
	pushd . > /dev/null
	cd "${CURL_VERSION}"
	./configure -prefix="/tmp/${CURL_VERSION}-${ARCH}" -disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/Mac ${NGHTTP2CFG} --host=${HOST} &> "/tmp/${CURL_VERSION}-${ARCH}.log"

	make -j8 >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	# Save curl binary for Mac Version
	cp "/tmp/${CURL_VERSION}-${ARCH}/bin/curl" "/tmp/curl"
	make clean >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1
    HOST=$2
    PLATFORM=$3

	pushd . > /dev/null
	cd "${CURL_VERSION}"

	if [ ! -z "$NGHTTP2" ]; then 
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/iOS/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/iOS/${ARCH}/lib"
	fi
	  
    SDKROOT="$(xcrun --sdk "$PLATFORM" --show-sdk-path)"
    export CC="$(xcrun -f clang)"

	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${SDKROOT} -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}" 
	export LDFLAGS="-arch ${ARCH} -isysroot ${SDKROOT} -L${OPENSSL}/iOS/lib ${NGHTTP2LIB}"
   
	echo "Building ${CURL_VERSION} for ${PLATFORM} ${IPHONEOS_DEPLOYMENT_TARGET} ${ARCH}"

    ./configure \
        -prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}" \
        --disable-shared \
        --enable-static \
        \
        --disable-debug \
        --enable-optimize \
        --enable-warnings \
        --disable-curldebug \
        --enable-symbol-hiding \
        \
        --disable-ares \
        \
        --enable-http \
        --disable-ftp \
        --disable-file \
        --disable-ldap \
        --disable-ldaps \
        --disable-rtsp \
        --disable-proxy \
        --disable-dict \
        --disable-telnet \
        --disable-tftp \
        --disable-pop3 \
        --disable-imap \
        --disable-smb \
        --disable-smtp \
        --disable-gopher \
        --disable-manual \
        --disable-libcurl-option \
        --enable-ipv6 \
        \
        --enable-threaded-resolver \
        --disable-sspi \
        --disable-crypto-auth \
        --disable-tls-srp \
        --with-ssl=${OPENSSL}/iOS \
        ${NGHTTP2CFG} \
        --host=${HOST} \
        &> "/tmp/${CURL_VERSION}-iOS-${ARCH}.log"

	make -j8 >> "/tmp/${CURL_VERSION}-iOS-${ARCH}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-iOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-iOS-${ARCH}.log" 2>&1
	popd > /dev/null
}

echo "Cleaning up"
rm -rf include/curl/* lib/*

mkdir -p lib
mkdir -p include/curl/

rm -rf "/tmp/${CURL_VERSION}-*"
rm -rf "/tmp/${CURL_VERSION}-*.log"

rm -rf "${CURL_VERSION}"

if [ ! -e ${CURL_VERSION}.tar.gz ]; then
	echo "Downloading ${CURL_VERSION}.tar.gz"
	curl -LO https://curl.haxx.se/download/${CURL_VERSION}.tar.gz
else
	echo "Using ${CURL_VERSION}.tar.gz"
fi

echo "Unpacking curl"
tar xfz "${CURL_VERSION}.tar.gz"

echo "Building Mac libraries"
buildMac x86_64 x86_64-apple-darwin

echo "Copying headers"
cp /tmp/${CURL_VERSION}-x86_64/include/curl/* include/curl/

lipo \
	"/tmp/${CURL_VERSION}-x86_64/lib/libcurl.a" \
	-create -output lib/libcurl_Mac.a

echo "Building iOS libraries"
buildIOS arm64 x86_64-apple-darwin
buildIOS x86_64 arm-apple-darwin iphoneos

lipo \
	"/tmp/${CURL_VERSION}-iOS-arm64/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-x86_64/lib/libcurl.a" \
	-create -output lib/libcurl_iOS.a

echo "Cleaning up"
rm -rf /tmp/${CURL_VERSION}-*
rm -rf ${CURL_VERSION}

echo "Checking libraries"
xcrun -sdk iphoneos lipo -info lib/*.a

#reset trap
trap - INT TERM EXIT

echo "Done"
