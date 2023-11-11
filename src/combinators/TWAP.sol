// SPDX-License-Identifier: GPL-v3.0
pragma solidity ^0.8.19;

import '../Feedbase.sol';
import { Ward } from '../mixin/ward.sol';

contract TWAP is Ward {
    struct Config {
        address source; // feedbase src
        bytes32 tag;    // feedbase tag
        uint256 range;  // [s] window size
        uint256 ttl;    // [s] ttl advance from latest spot
    }

    struct Window {
        uint head; // [ray] sum(p(t), 0, now) - sum(p(t), 0, t - range)
        uint time; // [s] head's last update timestamp
    }

    error ErrRange();
    error ErrDone();

    mapping(bytes32 dtag => Config)        configs;
    mapping(bytes32 dtag => Window) public windows;

    Feedbase public immutable feedbase;

    constructor(address _fb) Ward() {
        feedbase = Feedbase(_fb);
    }
    
    function setConfig(bytes32 dtag, Config calldata _config) public _ward_ {
        if (_config.range > block.timestamp) revert ErrRange();

        Window storage window = windows[dtag];
        window.time           = block.timestamp;
        if (configs[dtag].range > 0) {
            // new number of slots in window
            // do this so next poke result doesn't change
            window.head = window.head * _config.range / configs[dtag].range;
        }

        configs[dtag] = _config;
    }

    function getConfig(bytes32 tag) public view returns (Config memory) {
        return configs[tag];
    }

    // modified from reflexer ChainlinkTWAP
    // https://github.com/reflexer-labs/geb-chainlink-median/blob/master/src/ChainlinkTWAP.sol
    // GPL3
    //
    // this is similar to conventional TWAP algorithms that accumulate a
    // sum of prices over time, take the estimated change in the sum over the
    // window, and use that to calculate the mean
    //
    // the main difference here is that window stores `head`, an adjusted change
    // in sum since window start, instead of the sum itself
    function poke(bytes32 dtag) external {
        Config storage config    = configs[dtag];
        Window storage window    = windows[dtag];

        // pull latest spot
        (bytes32 spot, uint ttl) = feedbase.pull(config.source, config.tag);

        // pull head and elapsed time
        uint256 head    = window.head;
        uint256 elapsed = block.timestamp - window.time;
        uint256 capped  = elapsed > config.range ? config.range : elapsed;
        if (elapsed == 0) revert ErrDone();

        // estimate previous window spot, and checkpoint for new window start
        uint pseudospot = head / config.range;
        uint checkpoint = pseudospot * capped;

        // since head is a sum assuming 0 at window start,
        // need to subtract checkpoint to get head
        uint nexthead  = head + (capped * (uint(spot) + pseudospot)) / 2;
        nexthead      -= checkpoint;
        window.head    = nexthead;
        window.time    = block.timestamp;

        // handle a feed with updatedAt set to max uint
        unchecked {
            uint newttl = ttl + config.ttl;
            if (newttl < ttl) newttl = type(uint).max;
            ttl = newttl;
        }

        // have the integral's change over this window; push the mean
        feedbase.push(dtag, bytes32(nexthead / config.range), ttl);
    }
}
