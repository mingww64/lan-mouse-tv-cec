import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class HomeTop extends StatelessWidget {
  const HomeTop({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/logo.svg',
          width: 96,
        ),
        SizedBox(height: 16, width: MediaQuery.sizeOf(context).width),
        Text(
          "Lan Mouse CEC",
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          "Choose a Lan Mouse client. Keys and mouse are relayed only while its selected TV input is active.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
