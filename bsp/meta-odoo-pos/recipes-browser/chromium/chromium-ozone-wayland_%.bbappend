# Ensure the build-triplet clang runtime path exists when host and target arch match.
do_copy_clang_library:append() {
    src_dir="${STAGING_LIBDIR_NATIVE}/clang/latest/lib/linux"
    if [ ! -d "${src_dir}" ]; then
        return
    fi

    build_triplet="$(echo ${RUST_BUILD_SYS} | sed -e 's:-oe-:-unknown-:' -e 's:-poky-:-unknown-:')"

    for triplet in "${build_triplet}" "${BUILD_ARCH}-unknown-linux-gnu"; do
        if [ -z "${triplet}" ]; then
            continue
        fi

        dst_dir="${STAGING_LIBDIR_NATIVE}/clang/latest/lib/${triplet}"
        if [ -d "${dst_dir}" ]; then
            continue
        fi

        mkdir -p "${dst_dir}"
        cp -a "${src_dir}/." "${dst_dir}/"

        (
            cd "${dst_dir}" || exit 0
            for file in *-"${BUILD_ARCH}".a *-"${BUILD_ARCH}"hf.a; do
                if [ -f "${file}" ]; then
                    new_name=$(echo "${file}" | sed -e "s/-${BUILD_ARCH}hf//" -e "s/-${BUILD_ARCH}//")
                    mv "${file}" "${new_name}"
                fi
            done
        )
    done
}

# Enable CUPS backend so Chromium can list and use CUPS printers.
PACKAGECONFIG:append = " cups"
