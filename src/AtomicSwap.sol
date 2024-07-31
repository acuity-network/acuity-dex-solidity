// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./ERC20.sol";

contract AtomicSwap {

    /**
     * @dev Mapping of selling ERC20 contract address to buy assetId to linked list of sell orders, starting with the lowest selling price.
     */
    mapping (address => mapping (bytes32 => mapping (bytes32 => bytes32))) sellBuyOrderLL;

    mapping (address => mapping (bytes32 => mapping (bytes32 => uint))) sellBuyOrderValue;

    /**
     * @dev
     */
    error TokenTransferFailed(address token, address from, address to, uint value);

    /**
     * @dev
     */
    function safeTransfer(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transfer.selector, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, address(this), to, value);
    }

    /**
     * @dev
     */
    function safeTransferFrom(address token, address from, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transferFrom.selector, from, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, from, to, value);
    }

    function encodeOrder(address account, uint96 sellPrice) internal pure returns (bytes32 order) {
        order = bytes32(bytes20(account)) | bytes32(bytes12(sellPrice));
    }

    function decodeOrder(bytes32 order) internal pure returns (address account, uint96 sellPrice) {

    }

    function addSellOrder(address sellToken, bytes32 buyAssetId, uint96 sellPrice, uint value) external {
        safeTransferFrom(sellToken, msg.sender, address(this), value);

        bytes32 order = encodeOrder(msg.sender, sellPrice);

        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyAssetId];
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyAssetId];

        // Does this order already exist?
        if (orderValue[order] > 0) {
            orderValue[order] += value;
            return;
        }

        bytes32 prev = 0;
        bytes32 next = orderLL[prev];
        while (next != 0) {
            (, uint96 nextSellPrice) = decodeOrder(next);

            if (nextSellPrice > sellPrice) {
                break;
            }

            prev = next;
            next = orderLL[prev];
        }

        // Insert into linked list.
        orderLL[prev] = order;
        orderLL[order] = next;
        orderValue[order] = value;
    }

    function buy() external {}
}
