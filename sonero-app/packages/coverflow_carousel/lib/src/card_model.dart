import 'package:flutter/material.dart';

/// Internal data structure representing a card in the Coverflow layout.
///
/// Keeps track of the card's virtual ID/index, its calculated [zIndex] for
/// proper stacking order, and its [child] widget.
class CardModel {
  /// The virtual layout index of this card.
  ///
  /// Can be negative or exceed the total number of items when in infinite
  /// scroll mode.
  final int id;

  /// The sorting z-index value used to order cards from back to front.
  ///
  /// Calculated dynamically during build cycles based on the absolute distance
  /// from the currently focused center index. Higher values are rendered on top.
  double zIndex;

  /// The child widget displayed on this card.
  final Widget child;

  /// Creates a new [CardModel] instance.
  CardModel({required this.id, required this.child, this.zIndex = 0.0});
}
