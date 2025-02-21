// SPDX-License-Identifier: AGPL-3.0-only

using MerkleTrees as MerkleTrees;
using MorphoToken as MorphoToken;

methods {
    function prevRoot() external returns(bytes32) envfree;
    function currRoot() external returns(bytes32) envfree;
    function claimed(address) external returns(uint256) envfree;

    function MerkleTrees.getValue(address, address) external returns(uint256) envfree;
    function MerkleTrees.getHash(address, address) external returns(bytes32) envfree;
    function MerkleTrees.wellFormedPath(address, address, bytes32[]) external envfree;

    function MorphoToken.balanceOf(address) external returns(uint256) envfree;
}

// Check how updateRoot changes the storage.
rule updateRootStorageChange(env e, bytes32 _newRoot) {
    bytes32 rootBefore = currRoot();

    updateRoot(e, _newRoot);

    assert prevRoot() == rootBefore;
    assert currRoot() == _newRoot;
}

// Check an account claimed amount is correctly updated.
rule updatedClaimedAmount(env e, address _account, uint256 _claimable, bytes32[] _proof) {
    claim(e, _account, _claimable, _proof);

    assert _claimable == claimed(_account);
}

// Check an account can only claim greater amounts each time.
rule increasingClaimedAmounts(env e, address _account, uint256 _claimable, bytes32[] _proof) {
    uint256 claimed = claimed(_account);

    claim(e, _account, _claimable, _proof);

    assert _claimable > claimed;
}

// Check that claiming twice is equivalent to claiming once with the last amount.
rule claimTwice(env e1, env e2, env e3, address _account, uint256 _claim1, uint256 _claim2) {
    storage initStorage = lastStorage;

    bytes32[] _proof1; bytes32[] _proof2;
    claim(e1, _account, _claim1, _proof1);
    claim(e2, _account, _claim2, _proof2);
    assert _claim2 >= _claim1;

    storage afterBothStorage = lastStorage;

    bytes32[] _proof3;
    claim(e3, _account, _claim2, _proof3) at initStorage;

    assert lastStorage == afterBothStorage;
}

// Check that the transferred amount is equal to the claimed amount minus the previous claimed amount.
rule transferredTokens(env e, address _account, uint256 _claimable, bytes32[] _proof) {
    // Assume that the rewards distributor itself is not receiving the tokens, to simplify this rule.
    require _account != currentContract;

    uint256 balanceBefore = MorphoToken.balanceOf(_account);
    uint256 claimedBefore = claimed(_account);

    // Safe require because the sum is capped by the total supply.
    require balanceBefore + MorphoToken.balanceOf(currentContract) < 2^256;

    claim(e, _account, _claimable, _proof);

    uint256 balanceAfter = MorphoToken.balanceOf(_account);

    assert balanceAfter - balanceBefore == _claimable - claimedBefore;
}

rule claimCorrectness(env e, address _account, uint256 _claimable, bytes32[] _proof) {
    address prevTree; address prevNode;
    address currTree; address currNode;

    // Assume that prevRoot and currRoot correspond to prevTree and currTree.
    require MerkleTrees.getHash(prevTree, prevNode) == prevRoot();
    require MerkleTrees.getHash(currTree, currNode) == currRoot();

    // No need to make sure that currNode (resp prevNode) is equal to currRoot (resp prevRoot): one can pass an internal node instead.

    // Assume that prevTree and currTree are well-formed.
    MerkleTrees.wellFormedPath(prevTree, prevNode, _proof);
    MerkleTrees.wellFormedPath(currTree, currNode, _proof);

    claim(e, _account, _claimable, _proof);

    assert _claimable == MerkleTrees.getValue(prevTree, _account) ||
           _claimable == MerkleTrees.getValue(currTree, _account);
}
