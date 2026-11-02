import 'package:dart_ssi/credentials.dart';
import 'package:flutter/material.dart';
import 'package:id_ideal_wallet/basicUi/standard/footer_buttons.dart';
import 'package:id_ideal_wallet/basicUi/standard/secured_widget.dart';
import 'package:id_ideal_wallet/views/credential_detail.dart';
import 'package:id_ideal_wallet/views/credential_page.dart';

import '../l10n/app_localizations.dart';

/// What an OpenID4VCI issuer announces before the issuance: no values, only the names of the claims.
class OfferedCredentialPreview {
  final String name;
  final List<String> claimNames;

  const OfferedCredentialPreview(this.name, this.claimNames);
}

class CredentialOfferDialogNew extends StatefulWidget {
  const CredentialOfferDialogNew(
      {super.key,
      required this.credentials,
      this.previews = const [],
      this.oidcIssuer,
      this.requestOidcTan = false,
      this.isOid = false});

  final List<VerifiableCredential> credentials;
  final List<OfferedCredentialPreview> previews;
  final String? oidcIssuer;
  final bool requestOidcTan, isOid;

  @override
  CredentialOfferDialogNewState createState() =>
      CredentialOfferDialogNewState();
}

class CredentialOfferDialogNewState extends State<CredentialOfferDialogNew> {
  final TextEditingController controller = TextEditingController();

  List<Widget> buildCredentialInfo() {
    var info = <Widget>[];
    for (var c in widget.credentials) {
      if (c.type.contains('PaymentReceipt')) continue;
      info.addAll([
        CredentialCard(
          credential: c,
          clickable: false,
        ),
        const SizedBox(
          height: 10,
        ),
        CredentialInfo(
          credential: c,
          showStatus: false,
        ),
        const SizedBox(
          height: 10,
        ),
      ]);
    }
    for (var p in widget.previews) {
      info.addAll([
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(p.name),
            subtitle:
                widget.oidcIssuer != null ? Text(widget.oidcIssuer!) : null,
            expandedAlignment: Alignment.centerLeft,
            children: p.claimNames
                .map((name) => ListTile(
                      visualDensity:
                          const VisualDensity(horizontal: 0, vertical: -4),
                      title: Text(name),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(
          height: 10,
        ),
      ]);
    }
    return info;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: SecuredWidget(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 10, 5, 0),
              child: Column(
                children: [
                  Text(
                    AppLocalizations.of(context)!.credentialOffer,
                    style: Theme.of(context).primaryTextTheme.headlineLarge,
                  ),
                  const SizedBox(height: 20),
                  ...buildCredentialInfo(),
                  if (widget.requestOidcTan)
                    ExpansionTile(
                        initiallyExpanded: true,
                        title: Text(
                          AppLocalizations.of(context)!.oidcTan,
                          style: Theme.of(context).primaryTextTheme.titleLarge,
                        ),
                        subtitle: Text(
                            AppLocalizations.of(context)!.oidcTanInfo,
                            style:
                                Theme.of(context).primaryTextTheme.titleMedium),
                        children: [
                          TextField(
                            onChanged: (text) {
                              controller.text = text;
                              setState(() {});
                            },
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(
                                borderSide:
                                    BorderSide(width: 2, color: Colors.grey),
                              ),
                            ),
                            controller: controller,
                          )
                        ]),
                ],
              ),
            ),
          ),
        ),
      ),
      persistentFooterButtons: [
        FooterButtons(
            positiveText: AppLocalizations.of(context)!.accept,
            positiveFunction: () => Navigator.of(context)
                .pop(widget.requestOidcTan ? controller.text : true)),
      ],
    );
  }
}
