# AXIOM Protocol — PDF Generation
#
# Prerequisites:
#   sudo apt-get install texlive-latex-extra texlive-fonts-recommended texlive-xetex pandoc
#
# Usage:
#   make yellowpaper    # Generate Yellow Paper PDF
#   make whitepaper     # Generate White Paper PDF
#   make errors         # Generate Errors YP PDF
#   make sdk            # Generate SDK YP PDF
#   make all            # Generate all PDFs
#   make sign           # Sign all PDFs with PGP (detached signatures)
#   make clean          # Remove generated PDFs and signatures

PANDOC = pandoc
ENGINE = --pdf-engine=xelatex
TEMPLATE = --template=axiom-template.latex
COMMON = $(ENGINE) $(TEMPLATE) --toc --toc-depth=3 --listings
AUTHOR = AXIOM Project
DATE = December 31, 2025

# Document versions — independent from code version.
# Update these when the DOCUMENT changes, not the code.
YP_VERSION = Version 1.0
WP_VERSION = Version 2.28
ERR_VERSION = Version 1.0
SDK_VERSION = Version 1.0

DOCS_DIR = $(CURDIR)/..

PDFS = AXIOM_YellowPaper.pdf AXIOM_WhitePaper.pdf AXIOM_YellowPaper_Errors.pdf AXIOM_YellowPaper_SDK.pdf

.PHONY: all yellowpaper whitepaper errors sdk sign clean

all: yellowpaper whitepaper errors sdk

yellowpaper:
	cd $(CURDIR) && $(PANDOC) $(DOCS_DIR)/AXIOM_YellowPaper.md \
		$(COMMON) \
		-V title="Lambda Protocol — Yellow Paper" \
		-V author="$(AUTHOR)" \
		-V version="$(YP_VERSION)" \
		-V date="$(DATE)" \
		-o AXIOM_YellowPaper.pdf
	@echo "Generated: AXIOM_YellowPaper.pdf"

whitepaper:
	cd $(CURDIR) && $(PANDOC) $(DOCS_DIR)/AXIOM_WhitePaper.md \
		$(COMMON) \
		-V title="AXIOM — White Paper" \
		-V author="$(AUTHOR)" \
		-V version="$(WP_VERSION)" \
		-V date="$(DATE)" \
		-o AXIOM_WhitePaper.pdf
	@echo "Generated: AXIOM_WhitePaper.pdf"

errors:
	cd $(CURDIR) && $(PANDOC) $(DOCS_DIR)/AXIOM_YellowPaper_Errors.md \
		$(COMMON) \
		-V title="AXIOM — Structured Error Wire Format" \
		-V author="$(AUTHOR)" \
		-V version="$(ERR_VERSION)" \
		-V date="$(DATE)" \
		-o AXIOM_YellowPaper_Errors.pdf
	@echo "Generated: AXIOM_YellowPaper_Errors.pdf"

sdk:
	cd $(CURDIR) && $(PANDOC) $(DOCS_DIR)/AXIOM_YellowPaper_SDK.md \
		$(COMMON) \
		-V title="AXIOM — SDK Yellow Paper" \
		-V author="$(AUTHOR)" \
		-V version="$(SDK_VERSION)" \
		-V date="$(DATE)" \
		-o AXIOM_YellowPaper_SDK.pdf
	@echo "Generated: AXIOM_YellowPaper_SDK.pdf"

sign:
	@for pdf in $(PDFS); do \
		if [ -f "$$pdf" ]; then \
			gpg --yes --detach-sign "$$pdf" && \
			echo "Signed: $$pdf.sig"; \
		fi; \
	done
	@echo ""
	@echo "Verify with: gpg --verify <file>.pdf.sig <file>.pdf"

clean:
	rm -f *.pdf *.sig *.aux *.log *.out *.toc
