// SPDX-License-Identifier: GPL-v3.0

pragma solidity ^0.8.19;

import { Block } from '../mixin/Read.sol';

contract Multiplier is Block {
    constructor(address fb) Block(fb) {}

    function read(bytes32 tag)
      external view override returns (bytes32 val, uint256 minttl) {
        Config storage config = configs[tag];

        // pull first operand and ttl
        // need to do this because otherwise result has max uint ttl
        (val, minttl) = feedbase.pull(config.sources[0], config.tags[0]);
        uint res = uint(val);

        // multiply by the rest (ray precision)
        uint n = config.sources.length;
        for (uint i = 1; i < n;) {
            (bytes32 mul, uint ttl) = feedbase.pull(config.sources[i], config.tags[i]);
            res = res * uint(mul) / RAY;
            unchecked{ ++i; }

            if (ttl < minttl) minttl = ttl;
        }
        val = bytes32(res);
    }
}
