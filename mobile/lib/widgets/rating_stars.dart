import 'package:flutter/material.dart';

class RatingStars extends StatelessWidget {
  final double rating;
  final int count;
  final double size;
  const RatingStars({super.key, required this.rating, this.count = 0, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final full = rating.floor();
    final hasHalf = (rating - full) >= 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          if (i < full) return Icon(Icons.star, size: size, color: Colors.amber.shade700);
          if (i == full && hasHalf) return Icon(Icons.star_half, size: size, color: Colors.amber.shade700);
          return Icon(Icons.star_border, size: size, color: Colors.amber.shade700);
        }),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Text('${rating.toStringAsFixed(1)} ($count)', style: TextStyle(fontSize: size * 0.75, color: Colors.grey.shade700)),
        ] else ...[
          const SizedBox(width: 4),
          Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: size * 0.75, color: Colors.grey.shade700)),
        ]
      ],
    );
  }
}
