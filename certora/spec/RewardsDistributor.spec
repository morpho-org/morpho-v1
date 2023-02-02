using MerkleTree1 as T1
using MerkleTree2 as T2

using MorphoToken as MorphoToken

methods {
    MORPHO() returns address envfree
    currRoot() returns bytes32 envfree
    claimed(address) returns uint256 envfree
    claim(address, uint256, bytes32[]) envfree => DISPATCHER(true)
    claimOne(address, uint256, bytes32) envfree
    transfer(address, uint256) => DISPATCHER(true)

    T1.initialized() returns bool envfree
    T1.newAccount(address, uint256) envfree
    T1.newNode(address, address, address) envfree
    T1.setRoot(address) envfree
    T1.isWellFormed(address) returns bool envfree
    T1.findProof(address) returns bytes32[] envfree
    T1.getRoot() returns address envfree
    T1.getCreated(address) returns bool envfree
    T1.getLeft(address) returns address envfree
    T1.getRight(address) returns address envfree
    T1.getValue(address) returns uint256 envfree
    T1.getHash(address) returns bytes32 envfree
    T1.findAndClaimAt(address, address) envfree

    T2.initialized() returns bool envfree
    T2.newAccount(address, uint256) envfree
    T2.newNode(address, address, address) envfree
    T2.setRoot(address) envfree
    T2.isWellFormed(address) returns bool envfree
    T2.findProof(address) returns bytes32[] envfree
    T2.getRoot() returns address envfree
    T2.getCreated(address) returns bool envfree
    T2.getLeft(address) returns address envfree
    T2.getRight(address) returns address envfree
    T2.getValue(address) returns uint256 envfree
    T2.getHash(address) returns bytes32 envfree
    T2.findAndClaimAt(address, address) envfree


    MorphoToken.balanceOf(address) returns uint256 envfree

    keccak(bytes32 a, bytes32 b) => _keccak(a, b)
}

ghost _keccak(bytes32, bytes32) returns bytes32 {
    axiom forall bytes32 a1. forall bytes32 b1. forall bytes32 a2. forall bytes32 b2.
        _keccak(a1, b1) == _keccak(a2, b2) => a1 == a2 && b1 == b2;
}

rule noClaimAgain(address _account, uint256 _claimable, bytes32[] _proof) {
    env e;  uint256 claimed;

    require (claimed <= _claimable);

    claim(_account, _claimable, _proof);

    claim@withrevert(_account, claimed, _proof);

    assert lastReverted;
}

rule claimCorrectOne(address _account, uint256 _claimable, bytes32 _proof) {
    env e;
    address root;
    require root == T1.getRoot();
    require _account != 0;
    require T1.getHash(root) == currRoot();
    require T1.getRight(root) == _account;
    require T1.isWellFormed(root);
    require T1.isWellFormed(_account);

    claimOne(_account, _claimable, _proof);

    assert _claimable == T1.getValue(_account);
}

rule claimCorrectOneAlt(bytes32 claimable, bytes32 left, bytes32 left_alt, bytes32 right_hash, bytes32 currRoot) {
    env e;
    bytes32 left_hash; bytes32 left_alt_hash;
    require left_hash == _keccak(left, claimable);
    require left_alt_hash == _keccak(left_alt, claimable);
    require _keccak(left_hash, right_hash) == currRoot;
    require _keccak(left_alt_hash, right_hash) == currRoot;

    assert left_alt == left;
}

rule claimCorrectness(address _account, uint256 _claimable, bytes32[] _proof) {
    env e;
    require T1.getHash(T1.getRoot()) == currRoot();
    require T1.isWellFormed(_account); // can also assume that other accounts are well-formed

    claim(_account, _claimable, _proof);

    assert T1.getCreated(T1.getRoot());
    assert T1.getCreated(_account);
    assert _claimable == T1.getValue(_account);
}

// rule claimCorrectness(address _account, uint256 _claimable, bytes32[] _proof) {
//     env e;
//     require T1.getHash(T1.getRoot()) == currRoot();
//     require T2.getHash(T2.getRoot()) == prevRoot();
//     require T1.isWellFormed(_account) && T2.isWellFormed(_account); // can also assume that other accounts are well-formed

//     uint256 balanceBefore = MorphoToken.balanceOf(_account);
//     uint256 claimedBefore = claimed(_account);

//     claim(_account, _claimable, _proof);

//     uint256 balanceAfter = MorphoToken.balanceOf(_account);

//     assert balanceAfter - balanceBefore == _claimable - claimedBefore; 
//     assert (T1.getCreated(_account) && _claimable == T1.getValue(_account)) || 
//            (T2.getCreated(_account) && _claimable == T1.getValue(_account));
// }

rule claimCompleteness(address _account) {
    env e;
    require T1.getHash(T1.getRoot()) == currRoot();
    require T1.getCreated(_account);
    require T1.isWellFormed(_account); // can also assume that other accounts are well-formed

    T1.findAndClaimAt@withrevert(currentContract, _account);

    assert !lastReverted;
}
