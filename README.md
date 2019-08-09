# MimbleWimble on Ethereum with zk SNARKs

## Structure
- `circuits/`: Circuits
- `test/`: Test cases
- `Dockerfile`: Docker file to test Zokrates circuits

## Pre-requisite
Install docker and GNU Make

## Command

#### Make verifier contract

```shell
# Specify the circuit path to compile and export the verifier contract
make verifier circuit=YOUR_CIRCUIT_PATH

# Specify the output path
make verifier circuit=YOUR_CIRCUIT_PATH output=MyVerifier.sol
```
#### Make proof

```shell
# Specify the circuit path and arguments
make proof circuit=YOUR_CIRCUIT_PATH args='0 0 0 .. 0'

# Specify the output path
make proof circuit=YOUR_CIRCUIT_PATH args='0 0 0 .. 0' output=myProof.json
```