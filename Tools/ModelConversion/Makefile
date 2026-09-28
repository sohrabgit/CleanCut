# Converts the benchmark models into ../../Models (see convert.py).
PYTHON := .venv/bin/python

.PHONY: all u2netp isnet clean

all: $(PYTHON)
	$(PYTHON) convert.py

u2netp: $(PYTHON)
	$(PYTHON) convert.py U2Netp

isnet: $(PYTHON)
	$(PYTHON) convert.py ISNet

$(PYTHON): requirements.txt
	uv venv --python 3.12 .venv
	uv pip install --python $(PYTHON) -r requirements.txt

clean:
	rm -rf .venv weights build
