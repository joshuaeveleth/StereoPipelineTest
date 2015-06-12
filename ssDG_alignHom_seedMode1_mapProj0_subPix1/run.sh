#!/bin/bash

set -x verbose
rm -rfv run

stereo --enable-fill-holes ../data/WV01_11JAN131652275-P1BS-10200100104A0300.r12_crop.tif ../data/WV01_11JAN131653225-P1BS-1020010011862E00.r12_crop.tif ../data/WV01_11JAN131652275-P1BS-10200100104A0300.r12.xml ../data/WV01_11JAN131653225-P1BS-1020010011862E00.r12.xml run/run --stereo-file stereo.default --left-image-crop-win 1024 0 1024 1024 -t dg --alignment-method homography --corr-seed-mode 1 --subpixel-mode 1 --bundle-adjust-prefix ../data/run_dg_ba/run

point2dem run/run-PC.tif --nodata-value -32767 --t_srs '+proj=longlat +ellps=WGS84 +no_defs '

