enum ShopCategory { avatar, frame, pet }

class ShopItem {
  final String id;
  final String title;
  final String description;
  final ShopCategory category;
  final int price;
  final String iconCode;

  const ShopItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.price,
    required this.iconCode,
  });
}
