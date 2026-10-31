// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_login_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$DeviceLoginStore on DeviceLoginBase, Store {
  late final _$_statusAtom = Atom(
    name: 'DeviceLoginBase._status',
    context: context,
  );

  DeviceLoginStatus get status {
    _$_statusAtom.reportRead();
    return super._status;
  }

  @override
  DeviceLoginStatus get _status => status;

  @override
  set _status(DeviceLoginStatus value) {
    _$_statusAtom.reportWrite(value, super._status, () {
      super._status = value;
    });
  }

  late final _$_userCodeAtom = Atom(
    name: 'DeviceLoginBase._userCode',
    context: context,
  );

  String? get userCode {
    _$_userCodeAtom.reportRead();
    return super._userCode;
  }

  @override
  String? get _userCode => userCode;

  @override
  set _userCode(String? value) {
    _$_userCodeAtom.reportWrite(value, super._userCode, () {
      super._userCode = value;
    });
  }

  late final _$_verificationUriAtom = Atom(
    name: 'DeviceLoginBase._verificationUri',
    context: context,
  );

  String? get verificationUri {
    _$_verificationUriAtom.reportRead();
    return super._verificationUri;
  }

  @override
  String? get _verificationUri => verificationUri;

  @override
  set _verificationUri(String? value) {
    _$_verificationUriAtom.reportWrite(value, super._verificationUri, () {
      super._verificationUri = value;
    });
  }

  late final _$_errorMessageAtom = Atom(
    name: 'DeviceLoginBase._errorMessage',
    context: context,
  );

  String? get errorMessage {
    _$_errorMessageAtom.reportRead();
    return super._errorMessage;
  }

  @override
  String? get _errorMessage => errorMessage;

  @override
  set _errorMessage(String? value) {
    _$_errorMessageAtom.reportWrite(value, super._errorMessage, () {
      super._errorMessage = value;
    });
  }

  late final _$startAsyncAction = AsyncAction(
    'DeviceLoginBase.start',
    context: context,
  );

  @override
  Future<void> start() {
    return _$startAsyncAction.run(() => super.start());
  }

  late final _$DeviceLoginBaseActionController = ActionController(
    name: 'DeviceLoginBase',
    context: context,
  );

  @override
  void cancel() {
    final _$actionInfo = _$DeviceLoginBaseActionController.startAction(
      name: 'DeviceLoginBase.cancel',
    );
    try {
      return super.cancel();
    } finally {
      _$DeviceLoginBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''

    ''';
  }
}
