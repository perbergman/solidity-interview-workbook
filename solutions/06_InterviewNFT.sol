// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/*
 * INTERVIEW NOTES
 * - The exercise's design fork: ERC721URIStorage = per-token URI mapping
 *   (flexible, extra SSTOREs per mint — strings are multi-slot) vs a
 *   _baseURI() override deriving baseURI + tokenId (near-free, one IPFS
 *   directory; what 10k-style collections use). This solution picks storage.
 * - _safeMint calls the recipient's onERC721Received — an external call
 *   MID-MINT, i.e. a reentrancy vector (classic mint-limit bypass in NFT
 *   drops). Harmless here (role-gated, no caps) and nextTokenId++ happens
 *   first, but say the words "effects before interactions."
 * - supportsInterface override(A, B): both bases implement ERC165's
 *   introspection, so Solidity forces you to resolve the diamond; a single
 *   super call walks the C3-linearized chain so each base ORs in its IDs.
 * - Monotonic nextTokenId: IDs unique forever, never reused after burns.
 * - Left out deliberately, worth naming: supply cap, payable public mint,
 *   ERC721Enumerable (on-chain iteration is expensive — index events
 *   off-chain instead), and ERC-2981 royalties.
 */
contract InterviewNFT is ERC721URIStorage, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public nextTokenId;

    constructor(address admin) ERC721("Interview NFT", "INFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mint(address to, string calldata uri)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
