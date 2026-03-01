import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:micro_mobility_app/src/core/themes/colors.dart';

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black26,
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: const Color.fromARGB(85, 255, 255, 255),
            borderRadius: BorderRadius.circular(20)
          ),
          padding: const EdgeInsets.all(20),
          child: LoadingAnimationWidget.discreteCircle(
            color: AppColors.primary, 
            size: 40
          ),
        ),
      ),
    );
  }
}