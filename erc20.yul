pragma evm "cancun"

// 1. Define the external Oracle Interface for the Transformer
interface ITellor {
    method getDataBefore(bytes32 _queryId, uint256 _timestamp)
        external view returns (bytes _value, uint256 _timestampRetrieved)
}

contract DSU {
    // Constants defined via Enums for gas efficiency
    enum Config {
        STALENESS_AGE := 3600,
        TRANSFER_FEE_BPS := 10,  // 0.1%
        DECIMALS := 18
    }

    // Custom Errors supported by your parser
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed)
    error OwnableUnauthorizedAccount(address account)
    error StalePrice(uint256 price, uint256 timestamp)

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value)
    event Mint(address indexed to, uint256 dsuAmount)

    code {
        // Constructor logic
        let _priceFeed := decode_address(0)
        let _owner := decode_address(32)
        let _tellor := decode_address(64)
        let _collector := decode_address(96)

        sstore(0, _owner)     // slot 0: owner
        sstore(1, _tellor)    // slot 1: tellor oracle
        sstore(2, _collector) // slot 2: fee collector

        // Deploy Runtime
        datacopy(0, dataoffset("runtime"), datasize("runtime"))
        return(0, datasize("runtime"))

        function decode_address(offset) -> a {
            a := and(codecopy(offset, 32), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    object "runtime" {
        code {
            // Memory layout using Structs (yul.js feature)
            struct User memory {
                uint256 balance
                uint256 allowance
            }

            // Authorization Macro
            macro OnlyOwner() := {
                if iszero(eq(caller(), sload(0))) {
                    emit OwnableUnauthorizedAccount(caller())
                    revert(0, 0)
                }
            }

            // Main Dispatcher
            function main() {
                let sig := shr(224, calldataload(0))

                switch sig

                // transfer(address,uint256)
                case 0xa9059cbb {
                    let to := decode_address(4)
                    let amount := calldataload(36)
                    do_transfer(caller(), to, amount)
                    return_true()
                }

                // mintDSUWithETH() - Payable
                case 0x4647908b {
                    mint_with_eth()
                }

                // balanceOf(address)
                case 0x70a08231 {
                    let account := decode_address(4)
                    mstore(0, sload(balance_slot(account)))
                    return(0, 32)
                }

                default {
                    // receive() logic
                    if iszero(calldatasize()) { mint_with_eth() }
                    revert(0, 0)
                }
            }

            /* --- Internal Logic --- */

            function do_transfer(from, to, amount) {
                let from_slot := balance_slot(from)
                let bal := sload(from_slot)

                if lt(bal, amount) {
                    // Use your error builder
                    emit ERC20InsufficientBalance(from, bal, amount)
                    revert(0, 0)
                }

                // Transfer Fee Logic
                let fee := div(mul(amount, Config.TRANSFER_FEE_BPS), 10000)
                let finalAmount := sub(amount, fee)

                sstore(from_slot, sub(bal, amount))

                let to_slot := balance_slot(to)
                sstore(to_slot, add(sload(to_slot), finalAmount))

                // Fee collection
                let coll_slot := balance_slot(sload(2))
                sstore(coll_slot, add(sload(coll_slot), fee))

                emit Transfer(from, to, finalAmount)
            }

            function mint_with_eth() {
                if iszero(callvalue()) { revert(0, 0) }

                // Call Oracle via ITellor interface
                let tellor_addr := sload(1)
                // Use a macro to get the price
                let price := get_price(tellor_addr)

                let dsuAmount := mul(callvalue(), price)

                let slot := balance_slot(caller())
                sstore(slot, add(sload(slot), dsuAmount))

                emit Mint(caller(), dsuAmount)
            }

            /* --- Helper Functions --- */

            function balance_slot(account) -> slot {
                mstore(0, account)
                mstore(32, 0x100) // Base slot for balances
                slot := keccak256(0, 64)
            }

            function get_price(oracle) -> p {
                // Logic to call ITellor.getDataBefore
                // Standard Yul call using your interface helpers
                p := 2500 // Placeholder for example
            }

            function decode_address(offset) -> a {
                a := and(calldataload(offset), 0xffffffffffffffffffffffffffffffffffffffff)
            }

            function return_true() {
                mstore(0, 1)
                return(0, 32)
            }
        }
    }
}
