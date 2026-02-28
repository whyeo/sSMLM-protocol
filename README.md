# sSMLM-protocol (MAP Lab Modified Version)

A modified version of [sSMLM-protocol](https://github.com/FOIL-NU/sSMLM-protocol) adapted for MAP Lab workflows with core functionality retained for specific use cases.

## Original Description
Spectroscopic Single Molecule Localization Microscopy (sSMLM) extends traditional single molecule localization microscopy (SMLM) by adding a spectroscopic dimension to the localization process. This allows for the identification of different fluorophores based on their emission spectra, enabling multiplexed imaging of multiple targets in a single sample. This repository contains the accompanying software for processing sSMLM images captured with the DWP system, described in Song et al. 2022.

### Prerequisites
The accompanying software, `RainbowSTORM v2` requires at least MATLAB R2020b to run, and requires the following toolboxes:
- Curve Fitting Toolbox
- Statistics and Machine Learning Toolbox
- Text Analytics Toolbox
- Signal Processing Toolbox

The recommended MATLAB version is R2023b for the best compatibility with the software.

### Sample data
Sample data is provided in a separate repository, [sSMLM-protocol-sample](https://github.com/FOIL-NU/sSMLM-protocol-sample). Download the sample data and extract it to the same directory as the software if you would like to test the software with the sample data.

### License
Distributed under the GNU General Public License v3.0. See `LICENSE` for more information.

### References
Ki-Hee Song, Benjamin Brenner, Wei-Hong Yeo, Junghun Kweon, Zhen Cai, Yang Zhang, Youngseop Lee, Xusan Yang, Cheng Sun, Hao F. Zhang (2022). Monolithic dual-wedge prism-based spectroscopic single-molecule localization microscopy. Nanophotonics, 11(8), 1527–1535. [https://doi.org/10.1515/nanoph-2021-0541](https://doi.org/10.1515/nanoph-2021-0541)