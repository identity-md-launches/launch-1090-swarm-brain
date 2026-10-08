# Swarm brain (BRAIN)

`src/Token.sol:Token` is an immutable, fixed-supply ERC-20. Its constructor mints
the complete supply to `msg.sender`, the immediate deploying account or contract.

| Parameter | Value |
| --- | --- |
| Name | `Swarm brain` |
| Symbol | `BRAIN` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Minor-unit supply | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Production contract | `src/Token.sol:Token` |

## Behavior and assumptions

The brief is implemented as a standard ERC-20 with exact transfers: no transfer
fees, burns, rebases, transfer restrictions, or address exemptions. No owner,
administrator, minting entrypoint, pause, blacklist, proxy, or upgrade exists.
The internal mint function is used only during construction. Deployment through
a factory gives that factory the entire supply, irrespective of `tx.origin` or
the account that called the factory.

Transfers and approvals return `true` on success and revert with OpenZeppelin
ERC-20 custom errors on failure. Zero-value transfers between valid addresses
are supported and emit `Transfer`; self-transfers preserve balances. Transfers
to the zero address and approvals for the zero spender revert. Each `approve`
replaces the previous allowance, including revocation with `0`. A successful
`transferFrom` consumes a finite allowance; `type(uint256).max` remains unchanged
as an unlimited allowance. Failed transfers revert all effects, including
allowance changes. `approve` emits `Approval`; spending an allowance does not
emit a new `Approval` in this implementation, so integrations should query
`allowance` for its current value.

No external contracts, oracles, chain addresses, keys, recipient parameters,
environment variables, or post-deployment configuration are required by the
token. It makes no external calls. Transfers to a contract do not notify that
contract or verify that it can later transfer the tokens.

## Reproduce and verify

Install Foundry and provide Solidity **0.8.26** in its compiler cache. All
Solidity dependencies are included as ordinary files under `lib/`; no package
installation, submodules, or network access is needed once the compiler exists.

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, the Cancun EVM, optimization at 200 runs,
and `bytecode_hash = "none"`. FFI and filesystem cheatcode access are disabled.
The compiler is selected by version and is not included in this repository.

Unit and fuzz tests cover metadata, the sole constructor mint event, CREATE2
factory deployment, exact transfers, zero and self-transfers, approvals,
allowance exhaustion and revocation, insufficient funds, invalid recipients,
rollback on failure, and rejection of mint/burn/admin selectors. Stateful
invariants exercise transfers and approvals among four holders, checking fixed
total supply, balance conservation, and allowance consumption. The configured
campaigns run 256 cases per fuzz test and 128 sequences of depth 64 per invariant.
Tests create their own state and do not read or write environment variables.

The launch-flow test checks exact token movements for a factory, distributor,
claimant, and pool address. Its pool quantity is illustrative. It does not
implement a pool or execute a Uniswap swap. The provided protected suite depends
on the network's launch harness, contracts, and configuration and is run by that
verifier separately. This project supplies the token and its standalone tests.

Vendored dependencies retain upstream licenses and source text:

- OpenZeppelin Contracts `v5.0.2`: the ERC-20 and its five required supporting
  source/license files, under `lib/openzeppelin-contracts/` (MIT).
- Forge Standard Library `v1.9.7`: Solidity sources and licenses under
  `lib/forge-std/` (MIT or Apache-2.0), used only by tests.

Archive URLs, pinned tags, and SHA-256 digests are recorded in
`lib/dependencies.json`. Generated `out/` and `cache/` files are disposable.

## Deployment parameters and responsibilities

Build the creation bytecode with the pinned settings:

```sh
forge inspect src/Token.sol:Token bytecode
```

The artifact is `out/Token.sol/Token.json`. Deploy that creation bytecode with no
constructor arguments and no ETH value. For an IdentityMD custom launch, the
factory must be the immediate creator, so it receives the whole supply before
performing its distribution and pool operations. Use the token parameters in
the table above when preparing the separate launch manifest. This assignment
does not select a chain, pool parameters, allocation beyond the constructor
mint, or launch economics; those belong to the launch operator's configuration.
The target chain must support the configured Cancun EVM.

The deployer is responsible for choosing and verifying the intended chain and
creator, retaining control of the initial supply, and transferring it according
to the authorized distribution. An intermediate deployment helper receives the
tokens itself and must be able to forward them. No deploy script, wallet key,
broadcast transaction, or production address is included or needed to build.

### After launch

There are no owner settings or maintenance calls. The launch operator should
verify the deployed source with the pinned compiler settings and check the
name, symbol, decimals, total supply, constructor `Transfer` event, and actual
distribution. Holders control their balances and approvals; use allowances
appropriate to the intended spending and revoke them when no longer needed.
Changing a nonzero allowance has the standard ERC-20 transaction-ordering race;
setting it to zero and waiting for confirmation before setting a new amount
avoids overwriting a still-active allowance without an intervening revocation.

There is no recovery function for tokens accidentally transferred to this token
contract or to recipients that cannot move them, and no administrative way to
reverse transfers or recover lost keys. The operator is responsible for a
separate independent adversarial review before release involving others' funds.
Local Foundry build, unit/fuzz/invariant tests, and formatting checks are the
validation performed here; Slither and Mythril were not run. Passing tests is
not a security audit.
