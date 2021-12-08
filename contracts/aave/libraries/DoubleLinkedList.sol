// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

library DoubleLinkedList {
    struct Account {
        address id;
        address prev;
        address next;
        uint256 value;
    }

    struct List {
        mapping(address => Account) accounts;
        address head;
        address tail;
    }

    /** @dev Returns the `account` linked to `_id`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @return value The value of the account.
     */
    function getValueOf(List storage _list, address _id) internal view returns (uint256) {
        return _list.accounts[_id].value;
    }

    /** @dev Removes an account of the `_list`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @return bool Whether the account has been removed or not.
     */
    function remove(List storage _list, address _id) internal returns (bool) {
        if (_contains(_list, _id)) {
            Account memory account = _list.accounts[_id];

            if (account.prev != address(0)) _list.accounts[account.prev].next = account.next;
            else _list.head = account.next;
            if (account.next != address(0)) _list.accounts[account.next].prev = account.prev;
            else _list.tail = account.prev;

            delete _list.accounts[_id];
            return true;
        } else {
            return false;
        }
    }

    /** @dev Inserts an account in the `_list` at the right slot based on its `_value`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @param _value The value of the account.
     *  @param _maxIterations The max number of iterations.
     */
    function insertSorted(
        List storage _list,
        address _id,
        uint256 _value,
        uint256 _maxIterations
    ) internal {
        require(!_contains(_list, _id));

        uint256 numberOfIterations;
        Account memory current = _list.accounts[_list.head];
        while (
            numberOfIterations <= _maxIterations &&
            current.id != _list.tail &&
            current.value > _value
        ) {
            current = _list.accounts[current.next];
            numberOfIterations++;
        }

        address nextId;
        address prevId;
        if (numberOfIterations > _maxIterations || current.id == _list.tail) {
            prevId = _list.tail;
            nextId = address(0);
        } else {
            prevId = current.prev;
            nextId = current.id;
        }

        _list.accounts[_id] = Account(_id, prevId, nextId, _value);

        if (prevId != address(0)) _list.accounts[prevId].next = _id;
        else _list.head = _id;
        if (nextId != address(0)) _list.accounts[nextId].prev = _id;
        else _list.tail = _id;
    }

    /** @dev Returns the address at the head of the `_list`.
     *  @param _list The list to get the head.
     *  @return The address.
     */
    function getHead(List storage _list) internal view returns (address) {
        return _list.head;
    }

    /** @dev Returns whether or not the account is in the `_list`.
     *  @param _list The list to search in.
     *  @param _id The address of the account.
     *  @return whether or not the account is in the `_list`.
     */
    function _contains(List storage _list, address _id) private view returns (bool) {
        return _list.accounts[_id].id != address(0);
    }
}
