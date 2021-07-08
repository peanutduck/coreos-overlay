# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

CROS_WORKON_PROJECT="flatcar-linux/grub"
CROS_WORKON_REPO="git://github.com"
GRUB_AUTOGEN=1  # We start from Git, so always autogen.
GRUB_BOOTSTRAP=1
GRUB_AUTORECONF=1

if [[ ${PV} == 9999 ]]; then
	KEYWORDS="~amd64 ~arm64 ~x86"
else
	# CROS_WORKON_COMMIT="cf5ec588a4c22af2d7c3525873e26cbdafa656da"  # flatcar-master
	CROS_WORKON_COMMIT="ae94b97be2b81b625d6af6654d3ed79078b50ff6"
	KEYWORDS="amd64 arm64 x86"
fi
inherit cros-workon

if [[ -n ${GRUB_AUTOGEN} ]]; then
	PYTHON_COMPAT=( python{3_6,3_7} )
	WANT_LIBTOOL=none
	inherit autotools python-any-r1
fi

inherit autotools bash-completion-r1 flag-o-matic multibuild pax-utils toolchain-funcs

DEJAVU=dejavu-sans-ttf-2.37
UNIFONT=unifont-12.1.02
SRC_URI+=" fonts? ( mirror://gnu/unifont/${UNIFONT}/${UNIFONT}.pcf.gz )
	themes? ( mirror://sourceforge/dejavu/${DEJAVU}.zip )"

DESCRIPTION="GNU GRUB boot loader"
HOMEPAGE="https://www.gnu.org/software/grub/"

# Includes licenses for dejavu and unifont
LICENSE="GPL-3+ BSD MIT fonts? ( GPL-2-with-font-exception ) themes? ( CC-BY-SA-3.0 BitstreamVera )"
SLOT="2/${PVR}"
IUSE="device-mapper doc efiemu +fonts mount nls sdl test +themes truetype libzfs"

GRUB_ALL_PLATFORMS=( coreboot efi-32 efi-64 emu ieee1275 loongson multiboot qemu qemu-mips pc uboot xen xen-32 xen-pvh )

# Flatcar: Add arm64 to the list of platforms
GRUB_ALL_PLATFORMS+=( arm64 )

IUSE+=" ${GRUB_ALL_PLATFORMS[@]/#/grub_platforms_}"

REQUIRED_USE="
	grub_platforms_coreboot? ( fonts )
	grub_platforms_qemu? ( fonts )
	grub_platforms_ieee1275? ( fonts )
	grub_platforms_loongson? ( fonts )
"

BDEPEND="
	${PYTHON_DEPS}
	app-misc/pax-utils
	sys-devel/flex
	sys-devel/bison
	sys-apps/help2man
	sys-apps/texinfo
	grub_platforms_arm64? ( cross-aarch64-cros-linux-gnu/gcc )
	test? (
		app-admin/genromfs
		app-arch/cpio
		app-arch/lzop
		grub_platforms_efi-64? ( app-emulation/qemu[qemu_softmmu_targets_x86_64] )
		grub_platforms_pc? ( app-emulation/qemu[qemu_softmmu_targets_i386] )
		grub_platforms_arm64? ( app-emulation/qemu[qemu_softmmu_targets_aarch64] )
		dev-libs/libisoburn
		sys-apps/miscfiles
		sys-block/parted
		sys-fs/squashfs-tools[lzo,xz]
	)
	themes? (
		app-arch/unzip
		media-libs/freetype:2
		virtual/pkgconfig
	)
	truetype? ( virtual/pkgconfig )
"
DEPEND="
	app-arch/xz-utils
	>=sys-libs/ncurses-5.2-r5:0=
	grub_platforms_emu? (
		sdl? ( media-libs/libsdl )
	)
	device-mapper? ( >=sys-fs/lvm2-2.02.45 )
	libzfs? ( sys-fs/zfs:= )
	mount? ( sys-fs/fuse:0 )
	truetype? ( media-libs/freetype:2= )
	ppc? ( sys-apps/ibm-powerpc-utils sys-apps/powerpc-utils )
	ppc64? ( sys-apps/ibm-powerpc-utils sys-apps/powerpc-utils )
"
RDEPEND="${DEPEND}
	kernel_linux? (
		grub_platforms_efi-32? ( sys-boot/efibootmgr )
		grub_platforms_efi-64? ( sys-boot/efibootmgr )
	)
	!sys-boot/grub:0
	nls? ( sys-devel/gettext )
"
DEPEND+=" !!=media-libs/freetype-2.5.4"

RESTRICT="!test? ( test )"

QA_EXECSTACK="usr/bin/grub-emu* usr/lib/grub/*"
QA_PRESTRIPPED="usr/lib/grub/.*"
QA_MULTILIB_PATHS="usr/lib/grub/.*"
QA_WX_LOAD="usr/lib/grub/*"

pkg_setup() {
	:
}

src_unpack() {
	cros-workon_src_unpack
	pushd "${P}" >/dev/null || die
	local GNULIB_URI="https://git.savannah.gnu.org/git/gnulib.git"
	local GNULIB_REVISION=$(source bootstrap.conf >/dev/null; echo "${GNULIB_REVISION}")
	git-r3_fetch "${GNULIB_URI}" "${GNULIB_REVISION}"
	git-r3_checkout "${GNULIB_URI}" gnulib
	popd >/dev/null || die
	default
}

src_prepare() {
	default

	sed -i -e /autoreconf/d autogen.sh || die

	if [[ -n ${GRUB_AUTOGEN} || -n ${GRUB_BOOTSTRAP} ]]; then
		python_setup
	else
		export PYTHON=true
	fi

	if [[ -n ${GRUB_BOOTSTRAP} ]]; then
		eautopoint --force
		# export GNULIB_URL="https://git.savannah.gnu.org/git/gnulib.git/"
		AUTOPOINT=: AUTORECONF=: ./bootstrap || die
	elif [[ -n ${GRUB_AUTOGEN} ]]; then
		./autogen.sh || die
	fi

	if [[ -n ${GRUB_AUTORECONF} ]]; then
		eautoreconf
	fi
}

grub_do() {
	multibuild_foreach_variant run_in_build_dir "$@"
}

grub_do_once() {
	multibuild_for_best_variant run_in_build_dir "$@"
}

grub_configure() {
	local platform

	case ${MULTIBUILD_VARIANT} in
		efi*) platform=efi ;;
		xen-pvh) platform=xen_pvh ;;
		xen*) platform=xen ;;
		arm64) platform=efi ;;
		guessed) ;;
		*) platform=${MULTIBUILD_VARIANT} ;;
	esac

	case ${MULTIBUILD_VARIANT} in
		*-32)
			if [[ ${CTARGET:-${CHOST}} == x86_64* ]]; then
				local CTARGET=${CTARGET:-i386}
			fi ;;
		*-64)
			if [[ ${CTARGET:-${CHOST}} == i?86* ]]; then
				local CTARGET=${CTARGET:-x86_64}
				local -x TARGET_CFLAGS="-Os -march=x86-64 ${TARGET_CFLAGS}"
				local -x TARGET_CPPFLAGS="-march=x86-64 ${TARGET_CPPFLAGS}"
			fi ;;
		arm64)
			local CTARGET=aarch64-cros-linux-gnu ;;
	esac

	local myeconfargs=(
		--disable-werror
		--program-prefix=
		--libdir="${EPREFIX}"/usr/lib
		$(use_enable device-mapper)
		$(use_enable mount grub-mount)
		$(use_enable nls)
		$(use_enable themes grub-themes)
		$(use_enable truetype grub-mkfont)
		$(use_enable libzfs)
		$(use_enable sdl grub-emu-sdl)
		${platform:+--with-platform=}${platform}

		# Let configure detect this where supported
		$(usex efiemu '' '--disable-efiemu')
	)

	if use fonts; then
		ln -rs "${WORKDIR}/${UNIFONT}.pcf" unifont.pcf || die
	fi

	if use themes; then
		ln -rs "${WORKDIR}/${DEJAVU}/ttf/DejaVuSans.ttf" DejaVuSans.ttf || die
	fi

	local ECONF_SOURCE="${S}"
	econf "${myeconfargs[@]}"
}

src_configure() {
	# Bug 508758.
	replace-flags -O3 -O2

	# We don't want to leak flags onto boot code.
	export HOST_CCASFLAGS=${CCASFLAGS}
	export HOST_CFLAGS=${CFLAGS}
	export HOST_CPPFLAGS=${CPPFLAGS}
	export HOST_LDFLAGS=${LDFLAGS}
	unset CCASFLAGS CFLAGS CPPFLAGS LDFLAGS

	tc-ld-disable-gold #439082 #466536 #526348
	export TARGET_LDFLAGS="${TARGET_LDFLAGS} ${LDFLAGS}"
	unset LDFLAGS

	tc-export CC NM OBJCOPY RANLIB STRIP
	tc-export BUILD_CC BUILD_PKG_CONFIG

	MULTIBUILD_VARIANTS=()
	local p
	for p in "${GRUB_ALL_PLATFORMS[@]}"; do
		use "grub_platforms_${p}" && MULTIBUILD_VARIANTS+=( "${p}" )
	done
	[[ ${#MULTIBUILD_VARIANTS[@]} -eq 0 ]] && MULTIBUILD_VARIANTS=( guessed )
	grub_do grub_configure
}

src_compile() {
	# Sandbox bug 404013.
	use libzfs && addpredict /etc/dfs:/dev/zfs

	grub_do emake
	use doc && grub_do_once emake -C docs html
}

src_test() {
	# The qemu dependency is a bit complex.
	# You will need to adjust QEMU_SOFTMMU_TARGETS to match the cpu/platform.
	grub_do emake check
}

src_install() {
	grub_do emake install DESTDIR="${D}" bashcompletiondir="$(get_bashcompdir)"
	use doc && grub_do_once emake -C docs install-html DESTDIR="${D}"

	einstalldocs

	insinto /etc/default
	newins "${FILESDIR}"/grub.default-3 grub

	# https://bugs.gentoo.org/231935
	dostrip -x /usr/lib/grub
}

pkg_postinst() {
	elog "For information on how to configure GRUB2 please refer to the guide:"
	elog "    https://wiki.gentoo.org/wiki/GRUB2_Quick_Start"

	if has_version 'sys-boot/grub:0'; then
		elog "A migration guide for GRUB Legacy users is available:"
		elog "    https://wiki.gentoo.org/wiki/GRUB2_Migration"
	fi

	if [[ -z ${REPLACING_VERSIONS} ]]; then
		elog
		optfeature "detecting other operating systems (grub-mkconfig)" sys-boot/os-prober
		optfeature "creating rescue media (grub-mkrescue)" dev-libs/libisoburn
		optfeature "enabling RAID device detection" sys-fs/mdadm
	fi

	if has_version sys-boot/os-prober; then
		ewarn "Due to security concerns, os-prober is disabled by default."
		ewarn "Set GRUB_DISABLE_OS_PROBER=false in /etc/default/grub to enable it."
	fi
}
