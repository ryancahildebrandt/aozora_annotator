set fallback

TODAY := `date +'%y.%m.%d'`

default:
  just --list

build:
	go build . aozora_annotator

update:
	git add .
	git commit -m "$(TODAY)"
	git push cb main
	git push gh main
