input_bucket := ocr-docs
output_bucket := ocr-results
service_account := ocr-docs-admin
package := github.com/pckhoi/k8s-ocr-jobqueue
namespace := ocr-jobqueue

subscription = $(input_bucket)-read
bucket_watcher_package = $(package)/bucket-watcher@$(version)

tmp_dir := tmp

.PHONY: install uninstall clean

install: kustomization.yml

clean:
	rm -rf $(tmp_dir)

uninstall:
	gcloud iam service-accounts delete \
		$(service_account)@$(project_id).iam.gserviceaccount.com
	rm $(tmp_dir)/key.json

	gcloud pubsub subscriptions delete $(subscription) --project $(project_id)
	gcloud pubsub topics delete $(input_bucket) --project $(project_id)
	gsutil rm -r gs://$(output_bucket)
	gsutil rm -r gs://$(input_bucket)
	rm $(tmp_dir)/bucket.txt


$(tmp_dir)/bucket.txt: | $(tmp_dir)
	gsutil mb -p $(project_id) gs://$(input_bucket)
	gsutil mb -p $(project_id) gs://$(output_bucket)
	gsutil iam ch allUsers:objectViewer gs://$(output_bucket)
	gsutil notification create \
		-t $(input_bucket) -f json \
		-e OBJECT_FINALIZE gs://$(input_bucket)
	gcloud pubsub subscriptions create $(subscription) --topic=$(input_bucket) --project $(project_id)
	echo "$(input_bucket)" > $@
	echo "$(output_bucket)" >> $@

$(tmp_dir)/key.json: $(tmp_dir)/bucket.txt
	gcloud iam service-accounts create $(service_account) \
		--description="Read/write OCR data to storage buckets" \
		--display-name="OCR docs admin" \
		--project $(project_id)
	gcloud projects add-iam-policy-binding $(project_id) \
		--member="serviceAccount:$(service_account)@$(project_id).iam.gserviceaccount.com" \
		--role="roles/pubsub.subscriber"
	gcloud projects add-iam-policy-binding $(project_id) \
		--member="serviceAccount:$(service_account)@$(project_id).iam.gserviceaccount.com" \
		--role="roles/storage.objectAdmin"
	gcloud iam service-accounts keys create $@ \
		--iam-account=$(service_account)@$(project_id).iam.gserviceaccount.com

$(tmp_dir)/bucket_watcher.elf: | $(tmp_dir)
	CGO_ENABLED=0 GOARCH=amd64 GOOS=linux go build -a -o $@ $(bucket_watcher_package)

$(tmp_dir)/doctr: | $(tmp_dir)
	git clone https://github.com/mindee/doctr.git $@

$(tmp_dir)/doctr-api.imgtag: $(tmp_dir)/doctr
	docker build -t doctr-api -f $</Dockerfile-api $(dir $<)
	docker images --format '{{.ID}}' doctr-api:latest > $@
	docker tag doctr-api:latest doctr-api:$$(cat $@)

$(tmp_dir)/bucket-watcher.imgtag: $(tmp_dir)/bucket_watcher.elf
	docker build -t bucket-watcher -f bucket_watcher.Dockerfile $(dir $<)
	docker images --format '{{.ID}}' bucket-watcher:latest > $@
	docker tag bucket-watcher:latest bucket-watcher:$$(cat $@)

define push_set_image
docker tag $(1):$(2) gcr.io/$(project_id)/$(1):$(2)
docker push gcr.io/$(project_id)/$(1):$(2)
kustomize edit set image $(1)=gcr.io/$(project_id)/$(1):$(2)
endef

kustomization.yml: $(tmp_dir)/doctr-api.imgtag $(tmp_dir)/bucket-watcher.imgtag $(tmp_dir)/key.json
	echo "namespace: $(namespace)" > $@
	echo "resources:" >> $@
	echo -e "\t- https://$(package)/releases/download/$(version)/resources.yml" >> $@
	$(call push_set_image,bucket-watcher,$(file $(tmp_dir)/bucket-watcher.imgtag))
	$(call push_set_image,doctr-api,$(file $(tmp_dir)/doctr-api.imgtag))
	kustomize edit add secret service-account-key --from-file=key.json=$(tmp_dir)/key.json

$(tmp_dir): ; @-mkdir $@ 2>/dev/null
