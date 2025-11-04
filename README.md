# Yield Vault (ERC4626)

## Requirements
- Install [Foundry](https://book.getfoundry.sh/getting-started/installation)

## Setup
- Run `forge install` to install required dependencies.

## Test
- Run ` forge test` to execute all tests.

## Coverage
- Run `forge coverage` to check code-coverage
- To generate a graphical front-end for the coverage report using `lcov`.
  - Install [lcov](https://formulae.brew.sh/formula/lcov)
  - A `lcov.info` file is included in this repository. The following command will generate the graphical report from this file:
  - Run `forge coverage --report lcov && genhtml lcov.info --branch --output-dir coverage --rc derive_function_end_line=0`
  - Open the `report/index.html` file in your browser to view the coverage report.