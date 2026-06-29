DIST = slides
TRASHEXT = .pdf .aux .log .nav .out .snm .toc
OUTDIR = texfiles

all: $(DIST).pdf
$(DIST).pdf: $(DIST).tex
	test -d $(OUTDIR) || mkdir $(OUTDIR)
	pdflatex -output-directory $(OUTDIR) $<
	pdflatex -output-directory $(OUTDIR) $< # Twice, so TOC is also updated
	cp $(OUTDIR)/$(DIST).pdf .

.PHONY: clean watch

watch:
	latexmk -pvc -pdf $(DIST).tex
clean:
	rm -rf $(OUTDIR)
	rm -f $(DIST).pdf
