export PATH := "/home/user/.cargo/bin:/home/linuxbrew/.linuxbrew/bin:" + env_var("PATH")

recipe := "recipes/recipe.yml"
image_name := "localhost/secureblue"
image_tag := "latest"
registry_port := "5000"

# Build the OCI image locally from the recipe
build:
    bluebuild build {{recipe}}

# Quick smoke test - opens a root shell in the built image
run:
    podman run --rm -it {{image_name}}:{{image_tag}} bash

# Convert the locally built image to a bootable QCOW2 disk
build-disk: build
    mkdir -p output
    podman save {{image_name}}:{{image_tag}} | sudo podman load
    sudo podman run \
        --rm \
        --privileged \
        --security-opt label=type:unconfined_t \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        -v {{justfile_directory()}}/output:/output \
        -v {{justfile_directory()}}/vm-user.toml:/config.toml:ro \
        quay.io/centos-bootc/bootc-image-builder:latest \
        build --type qcow2 --rootfs btrfs --config /config.toml --output /output \
        {{image_name}}:{{image_tag}}
    sudo chown -R ${SUDO_UID}:${SUDO_GID} output/
    mv output/qcow2/disk.qcow2 output/secureblue.qcow2
    rmdir output/qcow2

# Launch the VM using virt-install with UEFI and SPICE graphics
vm:
    virt-install \
        --connect qemu:///session \
        --name secureblue-dev \
        --cpu host-model \
        --vcpus 4 \
        --memory 4096 \
        --import \
        --disk output/secureblue.qcow2,format=qcow2 \
        --os-variant fedora-eln \
        --graphics spice \
        --boot uefi \
        --check all=off

# Start a local registry and push the custom image to it
# Inside the VM, rebase with:
#   rpm-ostree rebase ostree-unverified-registry:10.0.2.2:{{registry_port}}/secureblue:latest
registry:
    podman run -d --rm --name secureblue-registry -p {{registry_port}}:5000 registry:2 2>/dev/null || true
    podman push {{image_name}}:{{image_tag}} localhost:{{registry_port}}/secureblue:latest --tls-verify=false
