# dedup-scan

This is the decided dedup strategy as one command — coarse by design (file-level, majority-overlap thresholds, no per-call noise). The stages are: (1) periphery dead-code (needs the repo's .periphery.yml), and (2) graph mining over graphify-out/graph.json for same-call-surface files with no edges between them. In stage (3), the top-K candidates are judged by claude ("DUPLICATE-INTENT / DISTINCT / PARTIAL"). Prereq: run graphify-repo on the target first. Report lands at <repo>/graphify-out/DEDUP_REPORT.md.

First real catch (8/12, kicker): tools/maestri-ax/ — seven standalone Swift files each reimplementing the same AXUIElement boilerplate, zero shared code. pot-mhm scans clean.
