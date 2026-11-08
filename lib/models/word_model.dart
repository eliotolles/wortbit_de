// lib/models/word_model.dart
// Strong-typed model for a German vocabulary entry.

class WordModel {
  final int id;

  /// "der" | "die" | "das" | "verb" | "adj" | "prep"
  final String article;

  final String german;
  final String plural;
  final String conjugation;
  final String meaningVi;
  final String exampleDe;
  final String exampleVi;
  final String level;

  const WordModel({
    required this.id,
    required this.article,
    required this.german,
    required this.plural,
    required this.conjugation,
    required this.meaningVi,
    required this.exampleDe,
    required this.exampleVi,
    required this.level,
  });

  factory WordModel.fromJson(Map<String, dynamic> json) {
    return WordModel(
      id: (json['id'] as num).toInt(),
      article: json['article'] as String,
      german: json['german'] as String,
      plural: json['plural'] as String? ?? '',
      conjugation: json['conjugation'] as String? ?? '',
      meaningVi: json['meaningVi'] as String,
      exampleDe: json['exampleDe'] as String,
      exampleVi: json['exampleVi'] as String,
      level: json['level'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'article': article,
      'german': german,
      'plural': plural,
      'conjugation': conjugation,
      'meaningVi': meaningVi,
      'exampleDe': exampleDe,
      'exampleVi': exampleVi,
      'level': level,
    };
  }
}
