pragma solidity >=0.4.21 < 0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ZkInterfaces.sol";

contract Ethereum934 {

    struct ERC20Pool {
        mapping(uint => bool) mmrRoots;
        mapping(uint => uint16) mmrWidths;
        mapping(uint => bool) coinbase;
        mapping(uint => bool) spentTags;
    }

    struct OptimisticRollUp {
        address erc20;
        address submitter;
        uint fee;
        uint prevRoot;
        uint newRoot;
        uint16 newWidth;
        uint timestamp;
        bool exist;
    }

    struct Proof {
        uint[2] a;
        uint[2][2] b;
        uint[2] c;
    }

    struct EllipticPoint {
        uint x;
        uint y;
    }

    struct MimblewimbleTx {
        uint fee;
        uint metadata;
        uint tag1; // tag derived from the spent TXO
        uint root1; // root where the spent TXO being included
        Proof inclusionProof1; // zk-SNARKs proof which hides the path and sibling data
        uint tag2;
        uint root2;
        Proof inclusionProof2;
        EllipticPoint output1; // Result TXO
        Proof rangeProof1; // Result TXO's value is between 0 and 100433627766186892221372630771322662657637687111424552206336
        EllipticPoint output2;
        Proof rangeProof2;
        EllipticPoint sigPoint; // Point on the elliptic curve of Schnorr Signature
        Proof txProof; // zk-SNARKs proof which hides the input TXOs while assuring it satisfies Mimblewimble protocol
    }

    ZkDeposit zkDeposit;
    ZkMimblewimble zkMimblewimble;
    ZkMMRInclusion zkMMRInclusion;
    ZkRangeProof zkRangeProof;
    ZkRollUp1 zkRollUp1;
    ZkRollUp2 zkRollUp2;
    ZkRollUp4 zkRollUp4;
    ZkRollUp8 zkRollUp8;
    ZkRollUp16 zkRollUp16;
    ZkWithdraw zkWithdraw;

    constructor(
        address zkDepositAddr,
        address zkRangeProofAddr,
        address zkMimblewimbleAddr,
        address zkMMRInclusionAddr,
        address zkRollUp1Addr,
        address zkRollUp2Addr,
        address zkRollUp4Addr,
        address zkRollUp8Addr,
        address zkRollUp16Addr,
        address zkWithdrawAddr
    ) public {
        zkDeposit = ZkDeposit(zkDepositAddr);
        zkRangeProof = ZkRangeProof(zkRangeProofAddr);
        zkMimblewimble = ZkMimblewimble(zkMimblewimbleAddr);
        zkMMRInclusion = ZkMMRInclusion(zkMMRInclusionAddr);
        zkRollUp1 = ZkRollUp1(zkRollUp1Addr);
        zkRollUp2 = ZkRollUp2(zkRollUp2Addr);
        zkRollUp4 = ZkRollUp4(zkRollUp4Addr);
        zkRollUp8 = ZkRollUp8(zkRollUp8Addr);
        zkRollUp16 = ZkRollUp16(zkRollUp16Addr);
        zkWithdraw = ZkWithdraw(zkWithdrawAddr);
    }

    mapping(address => ERC20Pool) pools;
    mapping(bytes32 => OptimisticRollUp) optimisticRollUps;
    mapping(address => uint) public deposits;
    uint challengePeriod = 100;

    event RollUp(address erc20, uint root, uint newRoot, uint items);
    event RollUpCandidate(address erc20, uint root, uint newRoot, uint items);
    event Mimblewimble(address erc20, uint txo);

    /** @dev Deposits ERC20 to the magical world with zkSNARKs.
      * @param erc20 Address of the ERC20 token.
      * @param amount Amount of token to deposit.
      * @param tag Newly generated TXO's y-axis value.
      * @param a zkSNARKs proof data.
      * @param b zkSNARKs proof data.
      * @param c zkSNARKs proof data.
      */
    function depositToMagicalWorld(
        address erc20,
        uint tag,
        uint amount,
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c
    ) public {
        ERC20Pool storage pool = pools[erc20];
        require(pool.coinbase[tag] == false, "TXO already exists");
        // Check Deposit TXO's value is same with the given amount
        require(
            zkDeposit.verifyTx(
                a,
                b,
                c,
                [tag, amount, 1]
            ), "Deposit ZKP fails"
        );
        // Transfer ERC20 token. It should have enough allowance
        IERC20(erc20).transferFrom(msg.sender, address(this), amount);
        // Record the TXO as valid
        pool.coinbase[tag] = true;
    }

    /** @dev Update MMR using zk-RollUp.
      */
    function rollUp1Mimblewimble(
        address erc20,
        uint root,
        uint newRoot,
        uint[52][1] memory mwTxs,
        uint[8] memory rollUpProof
    ) public {
        ERC20Pool storage pool = pools[erc20];

        uint[2] memory xItems;
        uint[2] memory yItems;
        for (uint8 i = 0; i < 1; i++) {
            MimblewimbleTx memory mwTx = toMimblewimbleTx(mwTxs[i]);
            require(verifyMimblewimbleTx(pool, mwTx), "Mimblewimble proof fails");
            xItems[2 * i + 0] = mwTx.output1.x;
            xItems[2 * i + 1] = mwTx.output2.x;
            yItems[2 * i + 0] = mwTx.output1.y;
            yItems[2 * i + 1] = mwTx.output2.y;
            emit Mimblewimble(erc20, mwTx.output1.y);
            emit Mimblewimble(erc20, mwTx.output2.y);
        }

        // Check roll up
        require(
            zkRollUp2.verifyTx(
                [rollUpProof[0], rollUpProof[1]],
                [[rollUpProof[2], rollUpProof[3]], [rollUpProof[4], rollUpProof[5]]],
                [rollUpProof[6], rollUpProof[7]],
                [root, pool.mmrWidths[root], xItems[0], xItems[1], yItems[0], yItems[1], newRoot, 1]
            ),
            "Roll up fails"
        );
        // Update root & width
        require(root == 1 || pool.mmrRoots[root], "Root does not exist");
        pool.mmrRoots[newRoot] = true;
        uint16 newWidth = pool.mmrWidths[root] + 2;
        require(newWidth < 66536, "This 16 bit MMR only contains 66535 items");
        pool.mmrWidths[newRoot] = newWidth;
        delete pool.mmrRoots[root];
        delete pool.mmrWidths[root];

        emit RollUp(erc20, root, newRoot, 1);
    }
    /** @dev Update MMR using zk-RollUp.
      */
    function rollUp2Mimblewimble(
        address erc20,
        uint root,
        uint newRoot,
        uint[52][2] memory mwTxs,
        uint[8] memory rollUpProof
    ) public {
        ERC20Pool storage pool = pools[erc20];

        uint[4] memory xItems;
        uint[4] memory yItems;
        for (uint8 i = 0; i < 2; i++) {
            MimblewimbleTx memory mwTx = toMimblewimbleTx(mwTxs[i]);
            require(verifyMimblewimbleTx(pool, mwTx), "Mimblewimble proof fails");
            xItems[2 * i + 0] = mwTx.output1.x;
            xItems[2 * i + 1] = mwTx.output2.x;
            yItems[2 * i + 0] = mwTx.output1.y;
            yItems[2 * i + 1] = mwTx.output2.y;
            emit Mimblewimble(erc20, mwTx.output1.y);
            emit Mimblewimble(erc20, mwTx.output2.y);
        }

        // Check roll up
        require(
            zkRollUp4.verifyTx(
                [rollUpProof[0], rollUpProof[1]],
                [[rollUpProof[2], rollUpProof[3]], [rollUpProof[4], rollUpProof[5]]],
                [rollUpProof[6], rollUpProof[7]],
                [root, pool.mmrWidths[root], xItems[0], xItems[1], xItems[2], xItems[3], yItems[0], yItems[1], yItems[2], yItems[3], newRoot, 1]
            ),
            "Roll up fails"
        );
        // Update root & width
        require(root == 1 || pool.mmrRoots[root], "Root does not exist");
        pool.mmrRoots[newRoot] = true;
        uint16 newWidth = pool.mmrWidths[root] + 4;
        require(newWidth < 66536, "This 16 bit MMR only contains 66535 items");
        pool.mmrWidths[newRoot] = newWidth;
        delete pool.mmrRoots[root];
        delete pool.mmrWidths[root];

        emit RollUp(erc20, root, newRoot, 2);
    }

    /** @dev Update MMR using zk-RollUp.
     */
    function rollUp4Mimblewimble(
        address erc20,
        uint root,
        uint newRoot,
        uint[52][4] memory mwTxs,
        uint[8] memory rollUpProof
    ) public {
        ERC20Pool storage pool = pools[erc20];

        uint[8] memory xItems;
        uint[8] memory yItems;
        for (uint8 i = 0; i < 4; i++) {
            MimblewimbleTx memory mwTx = toMimblewimbleTx(mwTxs[i]);
            require(verifyMimblewimbleTx(pool, mwTx), "Mimblewimble proof fails");
            xItems[2 * i + 0] = mwTx.output1.x;
            xItems[2 * i + 1] = mwTx.output2.x;
            yItems[2 * i + 0] = mwTx.output1.y;
            yItems[2 * i + 1] = mwTx.output2.y;
            emit Mimblewimble(erc20, mwTx.output1.y);
            emit Mimblewimble(erc20, mwTx.output2.y);
        }

        // Check roll up
        require(
            zkRollUp8.verifyTx(
                [rollUpProof[0], rollUpProof[1]],
                [[rollUpProof[2], rollUpProof[3]], [rollUpProof[4], rollUpProof[5]]],
                [rollUpProof[6], rollUpProof[7]],
                [root, pool.mmrWidths[root], xItems[0], xItems[1], xItems[2], xItems[3], xItems[4], xItems[5], xItems[6], xItems[7], yItems[0], yItems[1], yItems[2], yItems[3], yItems[4], yItems[5], yItems[6], yItems[7], newRoot, 1]
            ),
            "Roll up fails"
        );
        // Update root & width
        require(root == 1 || pool.mmrRoots[root], "Root does not exist");
        pool.mmrRoots[newRoot] = true;
        uint16 newWidth = pool.mmrWidths[root] + 8;
        require(newWidth < 66536, "This 16 bit MMR only contains 66535 items");
        pool.mmrWidths[newRoot] = newWidth;
        delete pool.mmrRoots[root];
        delete pool.mmrWidths[root];

        emit RollUp(erc20, root, newRoot, 4);
    }

    /** @dev Update MMR using zk-RollUp.
      */
    function rollUp8Mimblewimble(
        address erc20,
        uint root,
        uint newRoot,
        uint[52][8] memory mwTxs,
        uint[8] memory rollUpProof
    ) public {
        ERC20Pool storage pool = pools[erc20];

        uint[16] memory xItems;
        uint[16] memory yItems;
        for (uint8 i = 0; i < 8; i++) {
            MimblewimbleTx memory mwTx = toMimblewimbleTx(mwTxs[i]);
            require(verifyMimblewimbleTx(pool, mwTx), "Mimblewimble proof fails");
            xItems[2 * i + 0] = mwTx.output1.x;
            xItems[2 * i + 1] = mwTx.output2.x;
            yItems[2 * i + 0] = mwTx.output1.y;
            yItems[2 * i + 1] = mwTx.output2.y;
            emit Mimblewimble(erc20, mwTx.output1.y);
            emit Mimblewimble(erc20, mwTx.output2.y);
        }

        // Check roll up
        require(
            zkRollUp16.verifyTx(
                [rollUpProof[0], rollUpProof[1]],
                [[rollUpProof[2], rollUpProof[3]], [rollUpProof[4], rollUpProof[5]]],
                [rollUpProof[6], rollUpProof[7]],
                [root, pool.mmrWidths[root], xItems[0], xItems[1], xItems[2], xItems[3], xItems[4], xItems[5], xItems[6], xItems[7], xItems[8], xItems[9], xItems[10], xItems[11], xItems[12], xItems[13], xItems[14], xItems[15], yItems[0], yItems[1], yItems[2], yItems[3], yItems[4], yItems[5], yItems[6], yItems[7], yItems[8], yItems[9], yItems[10], yItems[11], yItems[12], yItems[13], yItems[14], yItems[15], newRoot, 1]
            ),
            "Roll up fails"
        );
        // Update root & width
        require(root == 1 || pool.mmrRoots[root], "Root does not exist");
        pool.mmrRoots[newRoot] = true;
        uint16 newWidth = pool.mmrWidths[root] + 16;
        require(newWidth < 66536, "This 16 bit MMR only contains 66535 items");
        pool.mmrWidths[newRoot] = newWidth;
        delete pool.mmrRoots[root];
        delete pool.mmrWidths[root];

        emit RollUp(erc20, root, newRoot, 8);
    }

    function optimisticRollUp8Mimblewimble(
        address erc20,
        uint root,
        uint newRoot,
        uint[52][8] memory mwTxs,
        uint[8] memory rollUpProof
    ) public {
        ERC20Pool storage pool = pools[erc20];
        bytes32 id = keccak256(msg.data);
        require(root == 1 || pool.mmrRoots[root], "Root does not exist");
        uint16 newWidth = pool.mmrWidths[root] + 16;
        require(newWidth < 66536, "This 16 bit MMR only contains 66535 items");

        uint fee = 0;
        for (uint8 i = 0; i < 8; i++) {
            fee += mwTxs[i][0];
        }
        OptimisticRollUp memory rollUp = OptimisticRollUp(
            erc20,
            msg.sender,
            fee,
            root,
            newRoot,
            newWidth,
            now,
            false
        );
        optimisticRollUps[id] = rollUp;
        emit RollUpCandidate(erc20, root, newRoot, 8);
    }

    function finalizeRollUp(bytes32 id) public {
        OptimisticRollUp storage rollUp = optimisticRollUps[id];
        ERC20Pool storage pool = pools[rollUp.erc20];
        require(now >= rollUp.timestamp + challengePeriod, "Still in challenge period");
        require(rollUp.exist, "Deleted or does not exist");
        // Update root & width
        require(rollUp.prevRoot == 1 || pool.mmrRoots[rollUp.prevRoot], "Root does not exist");
        pool.mmrRoots[rollUp.newRoot] = true;
        pool.mmrWidths[rollUp.newRoot] = rollUp.newWidth;
        delete pool.mmrRoots[rollUp.prevRoot];
        delete pool.mmrWidths[rollUp.prevRoot];

        emit RollUp(rollUp.erc20, rollUp.prevRoot, rollUp.newRoot, 1);
        IERC20(rollUp.erc20).transferFrom(address(this), rollUp.submitter, rollUp.fee);
        delete optimisticRollUps[id];
    }

    function challengeOptimisticRollUp8Mimblewimble(
        address erc20,
        uint root,
        uint newRoot,
        uint[52][8] memory mwTxs,
        uint[8] memory rollUpProof,
        uint challengeType
    ) public {
        if (challengeType == 0) {

        } else {

        }
    }


    /** @dev Withdraws ERC20 to the muggle world without revealing which TXO's been used.
      * @param erc20 Address of the ERC20 token.
      * @param tag y-axis value of the spent tag of a withdrawing TXO. Spent tag is calculated by r*(r*G+v*H).
      * @param value Value of the withdrawing TXO
      * @param root The MMR root which includes the withdrawing TXO
      * @param zkpA zkSNARKs proof data
      * @param zkpB zkSNARKs proof data
      * @param zkpC zkSNARKs proof data
      */
    function withdrawToMuggleWorld(
        address erc20,
        uint tag,
        uint value,
        uint root,
        uint[2] memory zkpA,
        uint[2][2] memory zkpB,
        uint[2] memory zkpC
    ) public {
        // Check double spending
        require(!pools[erc20].spentTags[tag], "Should not already have been spent");
        // Check the tag is derived from a unknown TXO belonging to the MMR trees
        require(zkWithdraw.verifyTx(zkpA, zkpB, zkpC, [root, tag, value, 1]), "Should satisfy the zkp condition");
        // Record as spent
        pools[erc20].spentTags[tag] = true;
        // Transfer
        IERC20(erc20).transfer(msg.sender, value);
    }

    function roots(address erc20, uint root) public view returns (bool) {
        ERC20Pool storage pool = pools[erc20];
        return pool.mmrRoots[root];
    }

    function width(address erc20, uint root) public view returns (uint16) {
        ERC20Pool storage pool = pools[erc20];
        return pool.mmrWidths[root];
    }


    function verifyTag(ERC20Pool storage pool, uint tag, uint root, Proof memory inclusionProof) internal returns (bool) {
        // Check double spending
        require(tag == 1 || pool.spentTags[tag] == false, "Already spent");
        // Check the root exists
        if (pool.coinbase[tag]) {
            //            delete pool.coinbase[tag];
            // Deposit tag
            return true;
        } else if (tag == 1) {
            // Dummy tag
            return true;
        } else {
            require(pool.mmrRoots[root], "Pool does not include the tag");
            // Check the spent tag is derived from an included item in the MMR
            require(
                zkMMRInclusion.verifyTx(inclusionProof.a, inclusionProof.b, inclusionProof.c, [root, tag, 1]),
                "Not sure that the root includes the hidden TXO"
            );
            return true;
        }
        return false;
    }

    function verifyMimblewimbleTx(ERC20Pool storage pool, MimblewimbleTx memory mwTx) internal returns (bool) {
        if (mwTx.tag1 != 1) {
            require(verifyTag(pool, mwTx.tag1, mwTx.root1, mwTx.inclusionProof1), "The tag is not valid");
            pool.spentTags[mwTx.tag1] = true;
        }
        if (mwTx.tag2 != 1) {
            require(verifyTag(pool, mwTx.tag2, mwTx.root2, mwTx.inclusionProof2), "The tag is not valid");
            pool.spentTags[mwTx.tag2] = true;
        }
        require(mwTx.tag1 != 1 || mwTx.tag2 != 1, "Tx should spent at least 1 TXO");

        // Check newly created TXOs' range proofs
        require(
            zkRangeProof.verifyTx(mwTx.rangeProof1.a, mwTx.rangeProof1.b, mwTx.rangeProof1.c, [mwTx.output1.y, 1]),
            "TXO's hidden value is not in the given range"
        );
        require(
            zkRangeProof.verifyTx(mwTx.rangeProof2.a, mwTx.rangeProof2.b, mwTx.rangeProof2.c, [mwTx.output2.y, 1]),
            "TXO's hidden value is not in the given range"
        );

        // Transaction can be included only in a given period;
        require(mwTx.metadata > block.number, "Expired");

        // Check this transaction satisfies the mimblewimble protocol
        require(
            zkMimblewimble.verifyTx(
                mwTx.txProof.a,
                mwTx.txProof.b,
                mwTx.txProof.c,
                [mwTx.fee, mwTx.metadata, mwTx.tag1, mwTx.tag2, mwTx.output1.x, mwTx.output1.y, mwTx.output2.x, mwTx.output2.y, mwTx.sigPoint.x, mwTx.sigPoint.y, 1]
            ), "Mimblewimble proof fails"
        );
        return true;
    }

    function toMimblewimbleTx(uint[52] memory data) internal pure returns (MimblewimbleTx memory) {
        return MimblewimbleTx(
            data[0],
            data[1],
            data[2],
            data[3],
            Proof([data[4], data[5]], [[data[6], data[7]], [data[8], data[9]]], [data[10], data[11]]),
            data[12],
            data[13],
            Proof([data[14], data[15]], [[data[16], data[17]], [data[18], data[19]]], [data[20], data[21]]),
            EllipticPoint(data[22], data[23]),
            Proof([data[24], data[25]], [[data[26], data[27]], [data[28], data[29]]], [data[30], data[31]]),
            EllipticPoint(data[32], data[33]),
            Proof([data[34], data[35]], [[data[36], data[37]], [data[38], data[39]]], [data[40], data[41]]),
            EllipticPoint(data[42], data[43]),
            Proof([data[44], data[45]], [[data[46], data[47]], [data[48], data[49]]], [data[50], data[51]])
        );
    }
}
