% AXIOM Protocol — LaTeX Document Class
% Used for Yellow Paper, White Paper, and SDK specifications.
%
% Usage:
%   \documentclass{axiom-paper}
%   \title{...}
%   \author{...}
%   \date{...}
%   \axiomversion{v2.11.16}
%
% Build:
%   xelatex paper.tex   (or: pandoc --template=axiom-template.tex -o paper.pdf)

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{axiom-paper}[2026/04/23 AXIOM Protocol Paper Class]

\LoadClass[11pt,a4paper]{article}

% ── Packages ──
\RequirePackage[margin=2.5cm]{geometry}
\RequirePackage{fontspec}           % XeTeX font selection
\RequirePackage{titlesec}           % Section formatting
\RequirePackage{fancyhdr}           % Headers/footers
\RequirePackage{hyperref}           % Clickable links
\RequirePackage{xcolor}             % Colors
\RequirePackage{graphicx}           % Images
\RequirePackage{longtable}          % Multi-page tables
\RequirePackage{booktabs}           % Professional tables
\RequirePackage{array}              % Table column formatting
\RequirePackage{calc}               % Length calculations in tables
\RequirePackage{listings}           % Code blocks
\RequirePackage{amsmath,amssymb}    % Math
\RequirePackage{tikz}               % Native diagrams
\usetikzlibrary{shapes.geometric,arrows.meta,positioning,shadows,fit,backgrounds}
\RequirePackage{enumitem}           % List formatting
\RequirePackage{float}              % Better figure placement

% Figures placed near their reference point but allowed to float within the page.
% Prevents both overlapping AND deferring to end of document.
\renewcommand{\fps@figure}{htbp}
\setcounter{topnumber}{3}           % Allow up to 3 floats at top of page
\setcounter{bottomnumber}{2}        % Allow up to 2 floats at bottom
\renewcommand{\topfraction}{0.85}   % Floats can take up to 85% of top
\renewcommand{\bottomfraction}{0.5} % Floats can take up to 50% of bottom
\renewcommand{\textfraction}{0.1}   % At least 10% text on a page with floats
\renewcommand{\floatpagefraction}{0.7} % Float-only pages must be 70% full
\RequirePackage{tocloft}            % ToC formatting
\RequirePackage{abstract}           % Abstract formatting
\RequirePackage{parskip}            % No indent, skip between paragraphs

% ── Colors ──
\definecolor{axiom-blue}{HTML}{1a365d}
\definecolor{axiom-gold}{HTML}{c4a035}
\definecolor{axiom-gray}{HTML}{4a5568}
\definecolor{axiom-light}{HTML}{f7fafc}
\definecolor{axiom-code}{HTML}{2d3748}

% ── Fonts ──
% TeX Gyre Pagella (Palatino) — heavier weight, authoritative feel.
% fontspec for XeTeX — full Unicode support (em-dashes, arrows, etc.)
\defaultfontfeatures{Ligatures=TeX}
\setmainfont{TeX Gyre Pagella}
\setmonofont{Hack}[Scale=0.85]     % Heavy monospace — thick strokes, high readability

% ── Hyperlinks ──
\hypersetup{
  colorlinks=true,
  linkcolor=axiom-blue,
  urlcolor=axiom-blue,
  citecolor=axiom-blue,
  pdftitle={AXIOM Protocol},
  pdfauthor={AXIOM Project}
}

% ── Headers & Footers ──
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\small\textcolor{axiom-gray}{AXIOM Protocol}}
\fancyhead[R]{\small\textcolor{axiom-gray}{\@axiomversion}}
\fancyfoot[C]{\small\textcolor{axiom-gray}{\thepage}}
\fancyfoot[R]{}
\renewcommand{\headrulewidth}{0.4pt}
\renewcommand{\footrulewidth}{0.2pt}

% ── Document version (independent from code version) ──
\newcommand{\@axiomversion}{Version 1.0}
\newcommand{\axiomversion}[1]{\renewcommand{\@axiomversion}{#1}}

% ── Document signing ──
% PDFs are signed with detached PGP signatures (make sign).
% No content hashes are embedded — the signature IS the proof.

% ── Section formatting ──
\titleformat{\section}
  {\Large\bfseries\color{axiom-blue}}
  {\thesection}{1em}{}
\titleformat{\subsection}
  {\large\bfseries\color{axiom-blue}}
  {\thesubsection}{1em}{}
\titleformat{\subsubsection}
  {\normalsize\bfseries\color{axiom-gray}}
  {\thesubsubsection}{1em}{}

% ── Inline code/variable style ──
% Black bold monospace — maximum contrast for variable names in prose.
\let\oldtexttt\texttt
\renewcommand{\texttt}[1]{%
  {\ttfamily\bfseries\color{black}#1}%
}

% ── Code listing style ──
\lstset{
  basicstyle=\ttfamily\small\color{axiom-code},
  backgroundcolor=\color{axiom-light},
  frame=single,
  framesep=4pt,
  framerule=0.4pt,
  rulecolor=\color{axiom-gray!30},
  breaklines=true,
  breakatwhitespace=true,
  tabsize=4,
  showstringspaces=false
}

% ── Title page ──
\renewcommand{\maketitle}{%
  \begin{titlepage}
    \centering
    \vspace*{4cm}

    {\Huge\bfseries\color{axiom-blue}\@title\par}
    \vspace{1cm}

    {\Large\color{axiom-gray}\@author\par}
    \vspace{0.2cm}
    {\small\ttfamily\color{axiom-gray!60}PGP: 029E 9BE8 569B 748A 1E75 8B38 86EF 3679 E216 16D8\par}
    \vspace{0.5cm}

    {\large\color{axiom-gray}\@axiomversion\par}
    \vspace{0.3cm}

    {\normalsize\color{axiom-gray}\@date\par}
    \vspace{2cm}

    \rule{0.6\textwidth}{0.4pt}
    \vspace{0.5cm}

    {\small\color{axiom-gray}%
      This document is the authoritative specification of the AXIOM protocol.\footnote{The protocol name is occasionally stylised as AXIØM in visual branding.}\\
      Any implementation that deviates from this specification is non-conformant.}

    \vfill

    {\footnotesize\color{axiom-gray}%
      AXIOM Project — TrustMesh Architecture\\
      \url{https://github.com/AXIOM-Origin-Validator}}
  \end{titlepage}
}

\endinput
