# Workaround for pseudo/fakeroot failure when using tar with Python 3.14
# This class provides a working perform_packagecopy function that doesn't rely on tar within fakeroot

python perform_packagecopy() {
    import shutil
    import os

    src = d.getVar('D')
    dest = d.getVar('PKGD')

    # Skip if source and dest are the same
    if not os.path.exists(src) or src == dest:
        return

    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest, exist_ok=True)

    # Copy all files directly using Python, no tar
    for root, dirs, files in os.walk(src):
        rel_root = os.path.relpath(root, src)
        dest_dir = dest if rel_root == '.' else os.path.join(dest, rel_root)

        for d_name in dirs:
            src_dir = os.path.join(root, d_name)
            dest_subdir = os.path.join(dest_dir, d_name)
            if not os.path.exists(dest_subdir):
                os.makedirs(dest_subdir, exist_ok=True)
                # Preserve permissions
                stat = os.stat(src_dir)
                os.chmod(dest_subdir, stat.st_mode)

        for f_name in files:
            src_file = os.path.join(root, f_name)
            dest_file = os.path.join(dest_dir, f_name)
            os.makedirs(os.path.dirname(dest_file), exist_ok=True)
            shutil.copy2(src_file, dest_file)
}

