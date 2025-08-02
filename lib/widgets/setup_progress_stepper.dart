import 'package:flutter/material.dart';

enum SetupStep { login, onboarding, sos, wakeword }

class SetupProgressStepper extends StatelessWidget {
  final SetupStep currentStep;

  const SetupProgressStepper({super.key, required this.currentStep});

  int get currentIndex => SetupStep.values.indexOf(currentStep);

  @override
  Widget build(BuildContext context) {
    final steps = [Icons.login, Icons.explore, Icons.contact_phone, Icons.mic];
    final totalSteps = steps.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final connectorWidth = (availableWidth - (totalSteps * 50)) / (totalSteps - 1);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(totalSteps * 2 - 1, (i) {
            if (i.isOdd) {
              final stepIndex = (i - 1) ~/ 2;
              final isCompleted = stepIndex < currentIndex;
              return Container(
                width: connectorWidth.clamp(10, 50),
                height: 2,
                color: isCompleted ? Colors.green : Colors.grey.shade300,
              );
            } else {
              final index = i ~/ 2;
              final isCompleted = index < currentIndex;
              final isCurrent = index == currentIndex;

              final circleColor = isCompleted
                  ? Colors.green
                  : isCurrent
                      ? const Color(0xFF2F67B5)
                      : Colors.grey.shade300;

              return CircleAvatar(
                radius: 25,
                backgroundColor: circleColor,
                child: Icon(steps[index], size: 30, color: Colors.white),
              );
            }
          }),
        );
      },
    );
  }
}
