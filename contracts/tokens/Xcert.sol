pragma solidity ^0.4.19;

import "../math/SafeMath.sol";
import "../ownership/Ownable.sol";
import "./ERC721.sol";
import "./ERC721Metadata.sol";
import "./ERC165.sol";
import "./ERC721TokenReceiver.sol";

/*
 * @title None-fungable token.
 * @dev Xcert is an implementation of EIP721 and EIP721Metadata. This contract follows
 * the implementation at goo.gl/FLaJc9.
 */
contract Xcert is Ownable, ERC721, ERC721Metadata, ERC165 {
  using SafeMath for uint256;

  /*
   * @dev A descriptive name for a collection of NFTs.
   */
  string private xcertName;

  /*
   * @dev An abbreviated name for NFTokens.
   */
  string private xcertSymbol;

  /*
   * @dev A mapping from NFToken ID to the address that owns it.
   */
  mapping (uint256 => address) internal idToOwner;

  /*
   * @dev Mapping from NFToken ID to approved address.
   */
  mapping (uint256 => address) internal idToApprovals;

  /*
   * @dev Mapping from owner address to count of his tokens.
   */
  mapping (address => uint256) internal ownerToNFTokenCount;

  /*
   * @dev Mapping from owner address to mapping of operator addresses.
   */
  mapping (address => mapping (address => bool)) internal ownerToOperators;

  /*
   * @dev Mapping from NFToken ID to metadata uri.
   */
  mapping (uint256 => string) internal idToUri;

  /*
   * @dev Mapping from NFToken ID to proof.
   */
  mapping (uint256 => string) internal idToProof;

  /*
   * @dev Mapping of supported intefraces.
   * You must not set element 0xffffffff to true.
   */
  mapping(bytes4 => bool) internal supportedInterfaces;

  /*
   * @dev Mapping of addresses authorized to mint new NFTokens.
   */
  mapping (address => bool) internal addressToMintAuthorized;

  /*
   * @dev Magic value of a smart contract that can recieve NFToken.
   */
  bytes4 private constant MAGIC_ONERC721RECEIVED = bytes4(
    keccak256("onERC721Received(address,uint256,bytes)")
  );

  /*
   * @dev This emits when ownership of any NFT changes by any mechanism.
   * This event emits when NFTs are created (`from` == 0) and destroyed
   * (`to` == 0). Exception: during contract creation, any number of NFTs
   * may be created and assigned without emitting Transfer. At the time of
   * any transfer, the approved address for that NFT (if any) is reset to none.
   */
  event Transfer(address indexed _from, address indexed _to, uint256 _tokenId);

  /*
   * @dev This emits when the approved address for an NFT is changed or
   * reaffirmed. The zero address indicates there is no approved address.
   * When a Transfer event emits, this also indicates that the approved
   * address for that NFT (if any) is reset to none.
   */
  event Approval(address indexed _owner, address indexed _approved, uint256 _tokenId);

  /*
   * @dev This emits when an operator is enabled or disabled for an owner.
   * The operator can manage all NFTs of the owner.
   */
  event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);

  /*
   * @dev This emits when an address is given authorization to mint new NFTokens or the
   * authorization is revoked.
   * The _target can mint new NFTokens.
   */
  event MintAuthorizedAddress(address indexed _target, bool _authorized);

  /*
   * @dev this emits everytime a new Xcert contract is deployed.
   */
  event XcertContractDeployed(address _contractAddress, string _name, string _symbol);

  /*
   * @dev Guarantees that the msg.sender is an owner or operator of the given NFToken.
   * @param _tokenId ID of the NFToken to validate.
   */
  modifier canOperate(uint256 _tokenId) {
    address owner = idToOwner[_tokenId];
    require(owner == msg.sender || ownerToOperators[owner][msg.sender]);
    _;
  }

  /*
   * @dev Guarantees that the msg.sender is allowed to transfer NFToken.
   * @param _tokenId ID of the NFToken to transfer.
   */
  modifier canTransfer(uint256 _tokenId) {
    address owner = idToOwner[_tokenId];
    require(
      owner == msg.sender
      || getApproved(_tokenId) == msg.sender
      || ownerToOperators[owner][msg.sender]
    );

    _;
  }

  /*
   * @dev Guarantees that _tokenId is a valid Token.
   * @param _tokenId ID of the NFToken to validate.
   */
  modifier validNFToken(uint256 _tokenId) {
    require(idToOwner[_tokenId] != address(0));
    _;
  }

  /*
   * @dev Guarantees that msg.sender is allowed to mint a new NFToken.
   */
  modifier canMint() {
    require(msg.sender == owner || addressToMintAuthorized[msg.sender]);
    _;
  }

  /*
   * @dev Contract constructor.
   * @param _name A descriptive name for a collection of NFTs.
   * @param _symbol An abbreviated name for NFTokens.
   */
  function Xcert(string _name, string _symbol)
    public
  {
    xcertName = _name;
    xcertSymbol = _symbol;
    supportedInterfaces[0x01ffc9a7] = true; // ERC165
    supportedInterfaces[0x6466353c] = true; // ERC721
    supportedInterfaces[0x5b5e139f] = true; // ERC721Metadata
    //TODO(Tadej): add for Xcert
    //supportedInterfaces[0x5b5e139f] = true; // ERC721Metadata
    XcertContractDeployed(address(this), _name, _symbol);
  }

  /*
   * @dev Returns the count of all NFTokens assigent to owner.
   * @param _owner Address where we are interested in NFTokens owned by them.
   */
  function balanceOf(address _owner)
    external
    view
    returns (uint256)
  {
    require(_owner != address(0));
    return ownerToNFTokenCount[_owner];
  }

  /*
   * @notice Find the owner of a NFToken.
   * @param _tokenId The identifier for a NFToken we are inspecting.
   */
  function ownerOf(uint256 _tokenId)
    external
    view
    returns (address _owner)
  {
    _owner = idToOwner[_tokenId];
    require(_owner != address(0));
  }

  /*
   * @notice Transfers the ownership of an NFT from one address to another address
   * @dev Throws unless `msg.sender` is the current owner, an authorized
   * operator, or the approved address for this NFT. Throws if `_from` is
   * not the current owner. Throws if `_to` is the zero address. Throws if
   * `_tokenId` is not a valid NFT. When transfer is complete, this function
   * checks if `_to` is a smart contract (code size > 0). If so, it calls
   * `onERC721Received` on `_to` and throws if the return value is not
   * `bytes4(keccak256("onERC721Received(address,uint256,bytes)"))`.
   * @param _from The current owner of the NFT
   * @param _to The new owner
   * @param _tokenId The NFT to transfer
   * @param data Additional data with no specified format, sent in call to `_to`
   */
  function safeTransferFrom(address _from,
                            address _to,
                            uint256 _tokenId,
                            bytes data)
    external
  {
    _safeTransferFrom(_from, _to, _tokenId, data);
  }

  /*
   * @notice Transfers the ownership of an NFT from one address to another address
   * @dev This works identically to the other function with an extra data parameter,
   * except this function just sets data to []
   * @param _from The current owner of the NFT
   * @param _to The new owner
   * @param _tokenId The NFT to transfer
   */
  function safeTransferFrom(address _from,
                            address _to,
                            uint256 _tokenId)
    external
  {
    _safeTransferFrom(_from, _to, _tokenId, "");
  }

  /*
   * @notice Transfer ownership of an NFT -- THE CALLER IS RESPONSIBLE
   * TO CONFIRM THAT `_to` IS CAPABLE OF RECEIVING NFTS OR ELSE
   * THEY MAY BE PERMANENTLY LOST
   * @dev Throws unless `msg.sender` is the current owner, an authorized
   * operator, or the approved address for this NFT. Throws if `_from` is
   * not the current owner. Throws if `_to` is the zero address. Throws if
   * `_tokenId` is not a valid NFT.
   * @param _from The current owner of the NFT
   * @param _to The new owner
   * @param _tokenId The NFT to transfer
   */
  function transferFrom(address _from,
                        address _to,
                        uint256 _tokenId)
    external
    canTransfer(_tokenId)
    validNFToken(_tokenId)
  {
    address owner = idToOwner[_tokenId];
    require(owner == _from);
    require(_to != address(0));

    _transfer(_to, _tokenId);
  }

  /*
   * @dev Approves another address to claim for the ownership of the given NFToken ID.
   * @param _to Address to be approved for the given NFToken ID.
   * @param _tokenId ID of the token to be approved.
   */
  function approve(address _approved, uint256 _tokenId)
    external
    canOperate(_tokenId)
    validNFToken(_tokenId)
  {
    address owner = idToOwner[_tokenId];
    require(_approved != owner);
    require(!(getApproved(_tokenId) == address(0) && _approved == address(0)));

    idToApprovals[_tokenId] = _approved;
    Approval(owner, _approved, _tokenId);
  }

  /*
   * @notice Enable or disable approval for a third party ("operator") to manage
   * all your asset.
   * @dev Emits the ApprovalForAll event
   * @param _operator Address to add to the set of authorized operators.
   * @param _approved True if the operators is approved, false to revoke approval
   */
  function setApprovalForAll(address _operator,
                             bool _approved)
    external
  {
    require(_operator != address(0));
    ownerToOperators[msg.sender][_operator] = _approved;
    ApprovalForAll(msg.sender, _operator, _approved);
  }

  /*
   * @dev Returns an address currently approved to take ownership of the given NFToken ID.
   * @param _tokenId ID of the NFToken to query the approval of.
   */
  function getApproved(uint256 _tokenId)
    public
    view
    validNFToken(_tokenId)
    returns (address)
  {
    return idToApprovals[_tokenId];
  }

  /*
   * @notice Query if an address is an authorized operator for another address
   * @param _owner The address that owns the NFTs
   * @param _operator The address that acts on behalf of the owner
   * @return True if `_operator` is an approved operator for `_owner`, false otherwise
   */
  function isApprovedForAll(address _owner,
                            address _operator)
    external
    view
    returns (bool)
  {
    require(_owner != address(0));
    require(_operator != address(0));
    return ownerToOperators[_owner][_operator];
  }

  /*
   * @dev Actually perform the safeTransferFrom.
   * @param _from The current owner of the NFT
   * @param _to The new owner
   * @param _tokenId The NFT to transfer
   * @param data Additional data with no specified format, sent in call to `_to`
   */
  function _safeTransferFrom(address _from,
                             address _to,
                             uint256 _tokenId,
                             bytes _data)
    internal
    canTransfer(_tokenId)
    validNFToken(_tokenId)
  {
    address owner = idToOwner[_tokenId];
    require(owner == _from);
    require(_to != address(0));

    _transfer(_to, _tokenId);

    // Do the callback after everything is done to avoid reentrancy attack
    uint256 codeSize;
    assembly { codeSize := extcodesize(_to) }
    if (codeSize == 0) {
        return;
    }
    bytes4 retval = ERC721TokenReceiver(_to).onERC721Received(_from, _tokenId, _data);
    require(retval == MAGIC_ONERC721RECEIVED);
  }

  /*
   * @dev Actually preforms the transfer. Does NO checks.
   * @param _to Address of a new owner.
   * @param _tokenId The NFToken that is being transferred.
   */
  function _transfer(address _to, uint256 _tokenId)
    private
  {
    address from = idToOwner[_tokenId];

    clearApproval(from, _tokenId);
    removeNFToken(from, _tokenId);
    addNFToken(_to, _tokenId);

    Transfer(from, _to, _tokenId);
  }

  /*
   * @dev Mints a new NFToken.
   * @param _to The address that will own the minted NFToken.
   * @param _id of the NFToken to be minted by the msg.sender.
   * @param _uri that points to NFToken metadata (optional, max length 2083).
   */
  function mint(address _to,
                uint256 _id,
                string _proof,
                string _uri)
    external
    canMint()
    returns (bool)
  {
    require(_to != address(0));
    require(_id != 0);
    require(idToOwner[_id] == address(0));
    require(utfStringLength(_uri) <= 2083);
    require(bytes(_proof).length > 0);

    idToUri[_id] = _uri;
    idToProof[_id] = _proof;
    addNFToken(_to, _id);

    Transfer(address(0), _to, _id);
    return true;
  }

  /*
   * @dev Gets proof for _tokenId.
   * @param _tokenId Id of the NFToken we want to get proof of.
   */
  function getProof(uint256 _tokenId)
    validNFToken(_tokenId)
    external
    view
    returns (string)
  {
    return idToProof[_tokenId];
  }

  /*
   * @dev Clears the current approval of a given NFToken ID.
   * @param _tokenId ID of the NFToken to be transferred.
   */
  function clearApproval(address _owner, uint256 _tokenId)
    internal
  {
    require(idToOwner[_tokenId] == _owner);
    delete idToApprovals[_tokenId];
    Approval(_owner, 0, _tokenId);
  }

  /*
   * @dev Removes a NFToken from owner.
   * @param _from Address from wich we want to remove the NFToken.
   * @param _tokenId Which NFToken we want to remove.
   */
  function removeNFToken(address _from, uint256 _tokenId)
   internal
  {
    require(idToOwner[_tokenId] == _from);

    ownerToNFTokenCount[_from] = ownerToNFTokenCount[_from].sub(1);
    delete idToOwner[_tokenId];
  }

  /*
   * @dev Assignes a new NFToken to owner.
   * @param _To Address to wich we want to add the NFToken.
   * @param _tokenId Which NFToken we want to add.
   */
  function addNFToken(address _to, uint256 _tokenId)
    private
  {
    require(idToOwner[_tokenId] == address(0));

    idToOwner[_tokenId] = _to;
    ownerToNFTokenCount[_to] = ownerToNFTokenCount[_to].add(1);
  }

  /*
   * @dev Calculates string length. This function is taken from https://goo.gl/dLgN7k.
   * A string is basically identical to bytes only that it is assumed to hold the UTF-8 encoding
   * of a real string. Since string stores the data in UTF-8 encoding it is quite expensive to
   * compute the number of characters in the string (the encoding of some characters takes more than
   * a single byte). Because of that, string s; s.length is not yet supported and not even index
   * access s[2]. But if you want to access the low-level byte encoding of the string, you can use
   * bytes(s).length and bytes(s)[2] which will result in the number of bytes in the UTF-8 encoding
   * of the string (not the number of characters) and the second byte (not character) of the UTF-8
   * encoded string, respectively.
   * This function takes the bytes and shifts them to check value and calculate te appropriate
   * length. Details can be found at https://goo.gl/MzagzL.
   * @param str UTF string we want the length of.
   */
  function utfStringLength(string _str)
    private
    pure
    returns (uint256 length)
  {
    uint256 i = 0;
    bytes memory stringRep = bytes(_str);

    while (i < stringRep.length) {
      if (stringRep[i] >> 7 == 0) {
        i += 1;
      } else if (stringRep[i] >> 5 == 0x6) {
        i += 2;
      } else if (stringRep[i] >> 4 == 0xE) {
        i += 3;
      } else if (stringRep[i] >> 3 == 0x1E) {
        i += 4;
      } else {
        i += 1;
      }
      length++;
    }
  }

  /*
   * @dev Returns a descriptive name for a collection of NFTokens.
   */
  function name()
    external
    view
    returns (string _name)
  {
    _name = xcertName;
  }

  /*
  * @notice Returns an abbreviated name for NFTokens.
  */
  function symbol()
    external
    view
    returns (string _symbol)
  {
    _symbol = xcertSymbol;
  }

  /*
   * @dev A distinct URI (RFC 3986) for a given NFToken.
   * @param _tokenId Id for which we want uri.
   */
  function tokenURI(uint256 _tokenId)
    external
    view
    returns (string)
  {
    require(idToOwner[_tokenId] != address(0));
    return idToUri[_tokenId];
  }

  /*
   * @dev Function to check which interfaces are suported by this contract.
   * @param interfaceID If of the interface.
   */
  function supportsInterface(bytes4 interfaceID)
    external
    view
    returns (bool)
  {
    return supportedInterfaces[interfaceID];
  }

  /*
   * @dev Sets mint authorised address.
   * @param _target Address to set authorized state.
   * @patam _authorized True if the _target is authorised, false to revoke authorization.
   */
  function setMintAuthorizedAddress(address _target,
                                    bool _authorized)
    external
    onlyOwner
  {
    require(_target != address(0));
    addressToMintAuthorized[_target] = _authorized;
    MintAuthorizedAddress(_target, _authorized);
  }

  /*
   * @dev Sets mint authorised address.
   * @param _target Address for which we want to check if it is authorized.
   * @return Is authorized or not.
   */
  function isMintAuthorizedAddress(address _target)
    external
    view
    returns (bool)
  {
    require(_target != address(0));
    return addressToMintAuthorized[_target];
  }
}
