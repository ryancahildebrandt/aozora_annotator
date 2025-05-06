# Aozora Bunko Text Annotator

---

[![Open in gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/ryancahildebrandt/aozora_annotator)
[![This project contains 0% LLM-generated content](https://brainmade.org/88x31-dark.png)](https://brainmade.org/)

## _Purpose_

This project seeks to reduce the sometimes innumerable number of trips back and forth between your favorite Japanese dictionary and the text you're reading. The included script parses a text from the Aozora Bunko literature corpus and looks up helpful information for terms in the text via the [Jotoba API](https://jotoba.de/docs.html#overview)

---

## Usage

Once you've cloned this repo and installed the necessary ruby gems (found in the Gemfile), you'll need to make sure you have a copy of the [Aozora Bunko database file](https://www.kaggle.com/datasets/ryancahildebrandt/azbcorpus) located in the ./data directory. Once you do, you can start annotating!

The easiest way to use this tool is via the command line. From the repo directory:

```bash
#to show all cli options and arguments
ruby azb.rb -h

#to search the database and return all texts with metainfo containing "源氏物語"
ruby azb.rb -s 源氏物語

#to pull information for text 165444, perform lookups, generate annotations, and render html and plaintext documents to the outputs directory
ruby azb.rb -i 165444

# to run the full pipeline as described above, this time with options!
ruby azb.rb -i 165444 -c -k -f 225%
```

Sometimes the api lookup behavior isn't perfect, so if you're planning on using this as a teaching aid or instructional materials, you can always fine tune the lookups by editing the json file after the initial lookup fetching

---

## Dataset

The dataset used for the current project was pulled from the following:

- [Aozora Bunko Corpus](https://www.kaggle.com/datasets/ryancahildebrandt/azbcorpus) for Japanese full texts
- [Jotoba](https://github.com/WeDontPanic/Jotoba) and [Jotoba API](https://jotoba.de/docs.html#overview) for looking up terms. Jotoba brings together information from a range of free sources including JMDict, Tofugu, and Tatoeba and all sources are listed [here](https://jotoba.de/about)

---

## Outputs

- Annotation format breakdown

  - Alternating
    - One term with its annotations immediately between it and the next term
    - term (annotation) term (annotation)
  - Layered
    - One sentence with all its annotations on the following line
    - sentence
    - (sentence annotations)
    - sentence
    - (sentence annotations)
  - Parallel
    - Full text with readings rendered above and meanings below, similar to the furigana annotation style commonly used
    - (sentence readings)
    - sentence
    - (sentence meanings)
  - Side by side
    - One sentence with all its annotations displayed on the right of the page
    - sentence || (sentence annotations)
    - sentence || (sentence annotations)

- Example outputs, generated from 三十三の死 by しづ素木:
  - [Alternating annotations](https://htmlpreview.github.io/?https://github.com/ryancahildebrandt/aozora_annotator/blob/main//outputs/000002_三十三の死_alternating.html) in HTML
  - [Layered annotations](https://htmlpreview.github.io/?https://github.com/ryancahildebrandt/aozora_annotator/blob/main//outputs/000002_三十三の死_layered.html) in HTML
  - [Parallel annotations](https://htmlpreview.github.io/?https://github.com/ryancahildebrandt/aozora_annotator/blob/main//outputs/000002_三十三の死_parallel.html) in HTML
  - [Side by side annotations](https://htmlpreview.github.io/?https://github.com/ryancahildebrandt/aozora_annotator/blob/main//outputs/000002_三十三の死_sidebyside.html) in HTML
  - [Unannotated](https://htmlpreview.github.io/?https://github.com/ryancahildebrandt/aozora_annotator/blob/main//outputs/000002_三十三の死_unannotated.html) in HTML
  - [Alternating annotations](./outputs/000002_三十三の死_alternating.txt) in plain text
  - [Layered annotations](./outputs/000002_三十三の死_layered.txt) in plain text
  - [Unannotated](./outputs/000002_三十三の死_unannotated.txt) in plain text
