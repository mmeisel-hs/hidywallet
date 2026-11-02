import 'package:dart_ssi/credentials.dart';
import 'package:dart_ssi/didcomm.dart';
import 'package:dart_ssi/wallet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:id_ideal_wallet/functions/util.dart';
import 'package:id_ideal_wallet/views/credential_offer_new.dart';
import 'package:uuid/uuid.dart';

import '../constants/server_address.dart';
import '../l10n/app_localizations.dart';
import '../provider/wallet_provider.dart';
import 'didcomm_message_handler.dart';

bool handleProposeCredential(ProposeCredential message, WalletProvider wallet) {
  throw Exception('We should never get such a message');
}

Future<bool> handleRequestCredential(
    RequestCredential message, WalletProvider wallet) async {
  String threadId;
  logger.d('Request Credential received');
  if (message.threadId != null) {
    threadId = message.threadId!;
  } else {
    threadId = message.id;
  }

  // Are there any previous messages?
  var entry = wallet.getConversation(threadId);

  // no -> This is a Problem: We have never offered sth.
  if (entry == null) {
    throw Exception('There is no offer');
  }

  var myDid = entry.myDid;

  var issueMessage = IssueCredential(
      threadId: threadId,
      credentials: [message.detail!.first.credential],
      replyUrl: '$relay/buffer/$myDid',
      from: myDid,
      to: [message.from!]);

  sendMessage(myDid, determineReplyUrl(message.replyUrl, message.replyTo),
      wallet, issueMessage, message.from!);

  return true;
}

Future<bool> handleOfferCredential(
    OfferCredential message, WalletProvider wallet) async {
  String threadId;
  logger.d('Offer Credential received');
  if (message.threadId != null) {
    threadId = message.threadId!;
  } else {
    threadId = message.id;
  }

  //Are there any previous messages?
  var entry = wallet.getConversation(threadId);
  String myDid;
  if (entry == null) {
    myDid = await wallet.newConnectionDid();
  } else {
    myDid = entry.myDid;
  }

  // credentials that have to be paid for are not supported
  if (message.attachments!.any((element) => element.format == 'lnInvoice')) {
    showErrorMessage(
        AppLocalizations.of(navigatorKey.currentContext!)!.noPaymentMethod);
    return false;
  }

  DidcommPlaintextMessage? lastMessage;
  if (entry != null) {
    lastMessage = DidcommPlaintextMessage.fromJson(entry.lastMessage);
  }
  logger.d(lastMessage?.type);
  //No
  if (lastMessage == null ||
      entry?.protocol == DidcommProtocol.discoverFeature.value ||
      lastMessage.attachments == null ||
      lastMessage.attachments!.isEmpty) {
    logger.d(message.fulfillment?.verifiableCredential);
    if (message.detail != null && message.detail!.isEmpty) {
      message.detail = null;
    }
    //show data to user
    var res = await showCupertinoModalPopup(
      context: navigatorKey.currentContext!,
      barrierColor: Colors.white,
      builder: (BuildContext context) => CredentialOfferDialogNew(
        credentials: message.detail?.map((e) => e.credential).toList() ??
            message.fulfillment?.verifiableCredential ??
            [],
      ),
    );

    if (res) {
      for (var entry in message.detail ?? <LdProofVcDetail>[]) {
        if (entry.credential.type.contains('PieceOfArt')) {
          wallet.addIssuanceProcess(threadId);
        }
      }
    } else {
      logger.d('user declined credential');
      var reply = determineReplyUrl(message.replyUrl, message.replyTo);
      var problem = ProblemReport(
          replyUrl: '$relay/buffer/$myDid',
          returnRoute: ReturnRouteValue.thread,
          to: [message.from!],
          from: myDid,
          parentThreadId: message.threadId ?? message.id,
          code: 'e.p.user.decline');

      // TODO: sendMessage(myDid, reply, wallet, problem, message.from!);
      return false;
    }
  } else if (lastMessage.type == DidcommMessages.requestCredential ||
      lastMessage.type == DidcommMessages.issueCredential) {
    showErrorMessage(
        AppLocalizations.of(navigatorKey.currentContext!)!.finishProcess,
        AppLocalizations.of(navigatorKey.currentContext!)!.finishProcessNote);
    return false;
  }

  //check, if we control did
  logger.d(message.detail);
  if (message.detail != null && message.detail!.isNotEmpty) {
    for (var credDetail in message.detail!) {
      var subject = credDetail.credential.credentialSubject;
      if (subject.containsKey('id')) {
        String id = subject['id'];
        //String? private;
        // try {
        //   private = await wallet.getPrivateKeyForCredentialDid(id);
        // } catch (e) {
        //   _sendProposeCredential(message, wallet, myDid);
        //   return false;
        // }
        if (!(await wallet.wallet.containsKey(id))) {
          _sendProposeCredential(message, wallet, myDid);
          return false;
        }
      } else {
        // Issuer likes to issue credential without id (not bound to holder)
        _sendRequestCredential(message, wallet, myDid);
        return false;
      }
    }
    await _sendRequestCredential(message, wallet, myDid);
  } else if (message.credentialManifest != null) {
    var request = RequestCredential(
        replyUrl: '$relay/buffer/$myDid',
        threadId: message.threadId ?? message.id,
        returnRoute: ReturnRouteValue.thread,
        parentThreadId: message.parentThreadId,
        from: myDid,
        to: [message.from!]);

    var con = wallet.getConnection(myDid);

    sendMessage(myDid, con!.otherDid, wallet, request, message.from!);
  }
  return false;
}

_sendRequestCredential(
  OfferCredential offer,
  WalletProvider wallet,
  String myDid,
) async {
  List<LdProofVcDetail> detail = [];
  for (var d in offer.detail!) {
    detail.add(LdProofVcDetail(
        credential: d.credential,
        options: LdProofVcDetailOptions(
            proofType: d.options.proofType,
            challenge: d.credential.proof == null
                ? const Uuid().v4()
                : d.credential.proof!.challenge!)));
  }
  var message = RequestCredential(
      detail: detail,
      replyUrl: '$relay/buffer/$myDid',
      threadId: offer.threadId ?? offer.id,
      returnRoute: ReturnRouteValue.thread,
      from: myDid,
      to: [offer.from!]);

  sendMessage(myDid, determineReplyUrl(offer.replyUrl, offer.replyTo), wallet,
      message, offer.from!);
}

_sendProposeCredential(
    OfferCredential offer, WalletProvider wallet, String myDid) async {
  List<LdProofVcDetail> detail = [];
  var firstDid = '';
  for (int i = 0; i < offer.detail!.length; i++) {
    var credDid = await wallet.newCredentialDid();
    if (i == 0) {
      firstDid = credDid;
    }
    var offeredCred = offer.detail![i].credential;
    logger.d('Das wurde angeboten: ${offeredCred.toJson()}');
    var credSubject = offeredCred.credentialSubject;
    logger.d(offeredCred.status);
    credSubject['id'] = credDid;
    var newCred = VerifiableCredential(
        id: credDid,
        context: offeredCred.context,
        type: offeredCred.type,
        issuer: offeredCred.issuer,
        credentialSubject: credSubject,
        issuanceDate: offeredCred.issuanceDate,
        credentialSchema: offeredCred.credentialSchema,
        status: offeredCred.status,
        expirationDate: offeredCred.expirationDate);
    logger.d('Das geht zurück : ${newCred.toJson()}');
    detail.add(LdProofVcDetail(
        credential: newCred, options: offer.detail!.first.options));
  }
  var message = ProposeCredential(
      threadId: offer.threadId ?? offer.id,
      from: myDid,
      to: [offer.from!],
      replyUrl: '$relay/buffer/$myDid',
      returnRoute: ReturnRouteValue.thread,
      detail: detail);

  //Sign attachment with credentialDid
  for (var a in message.attachments!) {
    await a.data.sign(wallet.wallet, firstDid);
    var verify = await a.data.verifyJws(firstDid);
    logger.d(verify);
  }

  logger.d(message.toJson());

  sendMessage(myDid, determineReplyUrl(offer.replyUrl, offer.replyTo), wallet,
      message, offer.from!);
}

Future<bool> handleIssueCredential(
    IssueCredential message, WalletProvider wallet) async {
  logger.d('Mir wurden Credentials ausgestellt');

  var entry = wallet.getConversation(message.threadId!);
  if (entry == null) {
    throw Exception(
        'Something went wrong. There could not be an issue message without request');
  }

  var previosMessage = DidcommPlaintextMessage.fromJson(entry.lastMessage);
  logger.d(previosMessage.type);
  if (previosMessage.type == DidcommMessages.requestCredential) {
    if (message.credentials != null && message.credentials!.isNotEmpty) {
      for (int i = 0; i < message.credentials!.length; i++) {
        var req = RequestCredential.fromJson(previosMessage.toJson());
        var cred = message.credentials![i];
        var challenge = req.detail![i].options.challenge;
        var verified = true;
        try {
          printWrapped(cred.toString());
          verified = await cred.verify(expectedChallenge: challenge);
        } catch (e) {
          showErrorMessage(
              AppLocalizations.of(navigatorKey.currentContext!)!
                  .wrongCredential,
              AppLocalizations.of(navigatorKey.currentContext!)!
                  .wrongCredentialNote);
          return false;
        }
        if (verified) {
          String? credDid = cred.credentialSubject['id'] ?? '';
          Credential? storageCred;
          if (credDid != '') {
            // storageCred = wallet.getCredential(credDid);
            // if (storageCred == null) {
            //   throw Exception(
            //       'No hd path for credential found. Sure we control it?');
            // }
          }

          var type = getTypeToShow(cred.type);
          if (credDid == '' || credDid == null) {
            credDid = '${cred.issuanceDate.toIso8601String()}$type';
          }

          logger.d(credDid);

          if (type == 'PaymentReceipt') {
            wallet.storeCredential(
              cred,
              credDid,
            );
          } else {
            wallet.storeCredential(cred, credDid);
            wallet.storeExchangeHistoryEntry(
                credDid, DateTime.now(), 'issue', message.from!);

            wallet.removeIssuanceProcess(message.threadId ?? '');

            showSuccessMessage(
                AppLocalizations.of(navigatorKey.currentContext!)!
                    .credentialReceived,
                type);
          }
        } else {
          showErrorMessage(
              AppLocalizations.of(navigatorKey.currentContext!)!
                  .wrongCredential,
              AppLocalizations.of(navigatorKey.currentContext!)!
                  .wrongCredentialNote);
          return false;
        }

        wallet.storeConversation(message, entry.myDid);

        if (message.pleaseAck != null && message.pleaseAck!.isNotEmpty) {
          var ack = EmptyMessage(
              from: entry.myDid,
              to: [message.from!],
              ack: [message.id],
              threadId: message.threadId ?? message.id);

          sendMessage(
              entry.myDid,
              determineReplyUrl(message.replyUrl, message.replyTo),
              wallet,
              ack,
              message.from!);
        }
      }
    }
  } else {
    throw Exception(
        'Issue credential could only follow to request credential message');
  }
  return false;
}
