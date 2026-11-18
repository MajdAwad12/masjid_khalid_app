import 'package:material_ui/material_ui.dart';

// Reusable input field for application forms.
class AppTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String label;
  final String? hintText;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextDirection? textDirection;
  final bool isPassword;
  final bool enabled;
  final bool readOnly;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;

  const AppTextField({
    super.key,
    this.controller,
    required this.label,
    this.hintText,
    this.prefixIcon,
    this.keyboardType,
    this.textInputAction,
    this.textDirection,
    this.isPassword = false,
    this.enabled = true,
    this.readOnly = false,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _passwordVisible = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textDirection: widget.textDirection,
      obscureText: widget.isPassword && !_passwordVisible,
      enableSuggestions: !widget.isPassword,
      autocorrect: !widget.isPassword,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,

      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,

        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),

        // Show or hide password.
        suffixIcon: widget.isPassword
            ? IconButton(
                tooltip: _passwordVisible
                    ? 'إخفاء كلمة المرور'
                    : 'إظهار كلمة المرور',
                icon: Icon(
                  _passwordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () {
                  setState(() {
                    _passwordVisible = !_passwordVisible;
                  });
                },
              )
            : null,
      ),
    );
  }
}
