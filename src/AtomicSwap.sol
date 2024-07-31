// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@polytope-labs/ismp-solidity/interfaces/IIsmpModule.sol";
import "./ERC20.sol";

contract AtomicSwap is IIsmpModule {

    struct Remittance {
        address account;
        uint value;
    }

    /**
     * @dev Mapping of selling ERC20 contract address to buy assetId to linked list of sell orders, starting with the lowest selling price.
     */
    mapping (address => mapping (bytes32 => mapping (bytes32 => bytes32))) sellBuyOrderLL;

    mapping (address => mapping (bytes32 => mapping (bytes32 => uint))) sellBuyOrderValue;

    address ismpHost;

    event PostReceived();
    event PostResponseReceived();
    event PostTimeoutReceived();
    event PostResponseTimeoutReceived();
    event GetResponseReceived();
    event GetTimeoutReceived();
    error NotAuthorized();

    /**
     * @dev
     */
    error TokenTransferFailed(address token, address from, address to, uint value);

    modifier onlyIsmpHost() {
        if (msg.sender != ismpHost) {
            revert NotAuthorized();
        }
        _;
    }
 
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

    constructor(address _ismpHost) {
        ismpHost = _ismpHost;
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

    function buy(address sellToken, bytes32 buyAssetId, uint buyValue, address buyer) internal returns (Remittance[] memory remittance) {
        // Linked list of sell orders for this pair, starting with the lowest price.
        mapping (bytes32 => bytes32) storage orderLL = sellBuyOrderLL[sellToken][buyAssetId];
        // Sell value of each sell order for this pair.
        mapping (bytes32 => uint) storage orderValue = sellBuyOrderValue[sellToken][buyAssetId];
        // Count the number of orders matched.
        uint orderCount = 0;
        uint buyValueTemp = buyValue;
        bytes32 order = orderLL[0];
        while (order != 0) {
            orderCount++;
            (address sellAccount, uint96 sellPrice) = decodeOrder(order);
            uint orderSellValue = orderValue[order];
            uint matchedSellValue = (buyValueTemp * 1 ether) / sellPrice;

            if (orderSellValue > matchedSellValue) {
                // Partial buy.
                break;
            }
            else {
                // Full buy.
                uint matchedBuyValue = (orderSellValue * sellPrice) / 1 ether;
                buyValueTemp -= matchedBuyValue;
                bytes32 next = orderLL[order];
            }
        }

        remittance = new Remittance[](orderCount);
        
        // Accumulator of how much of the sell token the buyer will receive.
        uint sellValue = 0;
        // Get the lowest sell order.
        order = orderLL[0];
        while (order != 0) {
            (address sellAccount, uint96 sellPrice) = decodeOrder(order);
            uint orderSellValue = orderValue[order];
            uint matchedSellValue = (buyValue * 1 ether) / sellPrice;

            if (orderSellValue > matchedSellValue) {
                // Partial buy.
                orderValue[order] -= matchedSellValue;
                // Transfer value.
                sellValue += matchedSellValue;
                remittance[0] = Remittance({
                    account: sellAccount,
                    value: buyValue
                });
                break;
            }
            else {
                // Full buy.
                uint matchedBuyValue = (orderSellValue * sellPrice) / 1 ether;
                buyValue -= matchedBuyValue;
                bytes32 next = orderLL[order];
                // Delete the sell order.
                orderLL[0] = next;
                delete orderLL[order];
                delete orderValue[order];
                order = next;
                // Transfer value.
                sellValue += orderSellValue;
                remittance[--orderCount] = Remittance({
                    account: sellAccount,
                    value: buyValue
                });
            }
        }

        if (sellValue > 0) {
            safeTransfer(sellToken, buyer, sellValue);
        }
    }

	/**
	 * @dev Called by the `IsmpHost` to notify a module of a new request the module may choose to respond immediately, or in a later block
	 * @param incoming post request
	 */
    function onAccept(IncomingPostRequest memory incoming) external onlyIsmpHost {
        // decode request body

        // Determine chain
        // Check message comes from correct contract
        // Determine sell token address
        address sellToken = address(0);
        
        // Determine buy assetId
        bytes32 buyAssetId = hex"1234";

        // Determine buy asset value.
        uint buyValue = 0;

        // Determine buyer address on this chain.
        address buyer = address(0);

        Remittance[] memory remittance = buy(sellToken, buyAssetId, buyValue, buyer);
        
        // Check that decoded value can be executed successfully
        // Make state changes
        emit PostReceived();
    }
    
    /**
	 * @dev Called by the `IsmpHost` to notify a module of a post response to a previously sent out request
	 * @param incoming post response
	 */
    function onPostResponse(IncomingPostResponse memory incoming) external onlyIsmpHost {
        // decode response
        // Check that decoded value can be executed successfully
        // Make state changes
        emit PostResponseReceived();
    }
 
    /**
	 * @dev Called by the `IsmpHost` to notify a module of a get response to a previously sent out request
	 * @param incoming get response
	 */
    function onGetResponse(IncomingGetResponse memory incoming) external onlyIsmpHost {
        emit GetResponseReceived();
    }
 
    /**
	 * @dev Called by the `IsmpHost` to notify a module of post requests that were previously sent but have now timed-out
	 * @param request post request
	 */
    function onPostRequestTimeout(PostRequest memory request) external onlyIsmpHost {
        // revert any state changes made when post request was dispatched
        emit PostTimeoutReceived();
    }
 
    /**
	 * @dev Called by the `IsmpHost` to notify a module of post requests that were previously sent but have now timed-out
	 * @param request post request
	 */
    function onPostResponseTimeout(PostResponse memory request) external onlyIsmpHost {
        // revert any state changes made when post response was dispatched
        emit PostResponseTimeoutReceived();
    }
 
    /**
	 * @dev Called by the `IsmpHost` to notify a module of get requests that were previously sent but have now timed-out
	 * @param request get request
	 */
    function onGetTimeout(GetRequest memory request) external onlyIsmpHost {
        // revert any state changes made when get request was dispatched
        emit GetTimeoutReceived();
    }
}
