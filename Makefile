BUILD_DIR := build
MD5_DIR := $(BUILD_DIR)/md5

.PHONY: all

all:

# calculate md5
$(MD5_DIR)/%.md5: % | $(MD5_DIR)
	@-mkdir -p $(dir $@) 2>/dev/null
	$(if $(filter-out $(shell cat $@ 2>/dev/null),$(shell $(MD5) $<)),$(MD5) $< > $@)

$(BUILD_DIR)/bucket_watcher.d: | $(BUILD_DIR)
	echo "SOURCES =" > $@
	echo "$$($(GO) list -deps github.com/pckhoi/k8s-ocr-jobqueue/bucket-watcher | \
		grep github.com/pckhoi/k8s-ocr-jobqueue/ | \
		sed -r -e 's/github.com\/pckhoi\/(.+)/\1/g' | \
		xargs -n 1 -I {} find {} -maxdepth 1 -name '*.go' \! -name '*_test.go' -print | \
		sed -r -e 's/(.+)/$(subst /,\/,SOURCES += $(MD5_DIR))\/\1.md5/g')" >> $@
	echo "" >> $@
	echo "\$$(BUILD_DIR)/bucket_watcher.elf: \$$(MD5_DIR)/go.sum.md5 \$$(SOURCES)" >> $@
	echo -e "\tCGO_ENABLED=0 GOARCH=amd64 GOOS=linux go build -a -o \$$@ github.com/pckhoi/k8s-ocr-jobqueue/bucket-watcher" >> $@
	echo "" >> $@

$(BUILD_DIR): ; @-mkdir $@ 2>/dev/null
$(MD5_DIR): | $(BUILD_DIR) ; @-mkdir $@ 2>/dev/null

include $(BUILD_DIR)/bucket_watcher.d