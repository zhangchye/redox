build/bootloader: bootloader/$(ARCH)/**
	mkdir -p build
	nasm -f bin -o $@ -D ARCH_$(ARCH) -ibootloader/$(ARCH)/ bootloader/$(ARCH)/disk.asm

build/harddrive.bin: build/filesystem.bin bootloader/$(ARCH)/**
	nasm -f bin -o $@ -D ARCH_$(ARCH) -D FILESYSTEM=$< -ibootloader/$(ARCH)/ bootloader/$(ARCH)/disk.asm

build/livedisk.bin: build/kernel_live bootloader/$(ARCH)/**
	nasm -f bin -o $@ -D ARCH_$(ARCH) -D KERNEL=$< -ibootloader/$(ARCH)/ bootloader/$(ARCH)/disk.asm

build/livedisk.iso: build/livedisk.bin.gz
	rm -rf build/iso/
	mkdir -p build/iso/
	cp -RL isolinux build/iso/
	cp $< build/iso/livedisk.gz
	genisoimage -o $@ -b isolinux/isolinux.bin -c isolinux/boot.cat \
					-no-emul-boot -boot-load-size 4 -boot-info-table \
					build/iso/
	isohybrid $@

bootloader-coreboot/build/bootloader: build/kernel_coreboot
	env --unset=RUST_TARGET_PATH --unset=RUSTUP_TOOLCHAIN --unset=XARGO_RUST_SRC \
	$(MAKE) -C bootloader-coreboot clean build/bootloader KERNEL="$(ROOT)/$<"

build/coreboot.elf: bootloader-coreboot/build/bootloader
	mkdir -p build
	cp -v $< $@

bootloader-efi/build/$(EFI_TARGET)/boot.efi: FORCE
	env --unset=RUST_TARGET_PATH --unset=RUSTUP_TOOLCHAIN --unset=XARGO_RUST_SRC \
	$(MAKE) -C bootloader-efi build/$(EFI_TARGET)/boot.efi TARGET=$(EFI_TARGET)

build/bootloader.efi: bootloader-efi/build/$(EFI_TARGET)/boot.efi
	mkdir -p build
	cp -v $< $@

build/harddrive-efi.bin: build/bootloader.efi build/filesystem.bin
	dd if=/dev/zero of=$@.partial bs=1048576 count=$$(expr $$(du -m $< | cut -f1) + 1)
	mkfs.vfat $@.partial
	mmd -i $@.partial efi
	mmd -i $@.partial efi/boot
	mcopy -i $@.partial $< ::efi/boot/bootx64.efi
	cat $@.partial build/filesystem.bin > $@

build/livedisk-efi.iso: build/bootloader.efi build/kernel_live
	dd if=/dev/zero of=$@.partial bs=1048576 count=$$(expr $$(du -mc $^ | grep 'total$$' | cut -f1) + 1)
	mkfs.vfat $@.partial
	mmd -i $@.partial efi
	mmd -i $@.partial efi/boot
	mcopy -i $@.partial $< ::efi/boot/bootx64.efi
	mmd -i $@.partial redox_bootloader
	mcopy -i $@.partial -s build/kernel_live ::redox_bootloader/kernel
	mv $@.partial $@
