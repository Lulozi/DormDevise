import 'package:flutter/material.dart';

class AddCourseDialog extends StatefulWidget {
  const AddCourseDialog({super.key});

  @override
  State<AddCourseDialog> createState() => _AddCourseDialogState();
}

class _AddCourseDialogState extends State<AddCourseDialog> {
  final _formKey = GlobalKey<FormState>();
  String name = '';
  String classroom = '';
  String teacher = '';
  int timeIndex = 1;
  String weekRange = '第 1-18 周';
  Color courseColor = const Color(0xFFFFAEBE);
  // 你可以根据需要添加更多字段

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF6F6F8),
      insetPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      child: SizedBox(
        width: double.infinity,
        height: MediaQuery.of(context).size.height,
        child: Column(
          children: [
            // 顶部自定义栏
            SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                color: const Color(0xFFF6F6F8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            color: Color(0xFF0099FF),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const Center(
                      child: Text(
                        '新建课程',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'MiSans',
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          if (_formKey.currentState?.validate() ?? false) {
                            _formKey.currentState?.save();
                            Navigator.pop(context, {
                              'name': name,
                              'teacher': teacher,
                              'classroom': classroom,
                              'timeIndex': timeIndex,
                              'weekRange': weekRange,
                              'courseColor': courseColor,
                            });
                          }
                        },
                        child: const Text(
                          '完成',
                          style: TextStyle(
                            color: Color(0xFFB0C4DE),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFEDEDED)),
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // 课程名
                      _InputGroup(
                        children: [
                          _InputRow(
                            label: '课程名',
                            hint: '必填',
                            onSaved: (v) => name = v ?? '',
                            validator: (v) =>
                                v == null || v.isEmpty ? '必填' : null,
                          ),
                        ],
                      ),
                      // 教室
                      _InputGroup(
                        children: [
                          _InputRow(
                            label: '教室',
                            hint: '非必填',
                            onSaved: (v) => classroom = v ?? '',
                          ),
                        ],
                      ),
                      // 备注
                      _InputGroup(
                        children: [
                          _InputRow(
                            label: '备注（如老师）',
                            hint: '非必填',
                            onSaved: (v) => teacher = v ?? '',
                          ),
                        ],
                      ),
                      // 时段
                      _InputGroup(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: const [
                                Text('时段', style: TextStyle(fontSize: 16)),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFEDEDED)),
                          InkWell(
                            onTap: () async {
                              // 这里可以弹出选择时段的弹窗
                              final result = await showDialog<int>(
                                context: context,
                                builder: (context) => SimpleDialog(
                                  title: const Text('选择课程时间'),
                                  children: List.generate(9, (i) {
                                    return SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(context, i + 1),
                                      child: Text('课程时间 ${i + 1}'),
                                    );
                                  }),
                                ),
                              );
                              if (result != null)
                                setState(() => timeIndex = result);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '课程时间 $timeIndex',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const Spacer(),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      // 上课周数
                      _InputGroup(
                        children: [
                          ListTile(
                            title: const Text(
                              '上课周数',
                              style: TextStyle(fontSize: 16),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  weekRange,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                            onTap: () async {
                              // 这里可以弹出选择周数的弹窗
                              final result = await showDialog<String>(
                                context: context,
                                builder: (context) => SimpleDialog(
                                  title: const Text('选择上课周数'),
                                  children: [
                                    SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(context, '第 1-18 周'),
                                      child: const Text('第 1-18 周'),
                                    ),
                                    SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(context, '第 1-8 周'),
                                      child: const Text('第 1-8 周'),
                                    ),
                                    // 可继续添加更多选项
                                  ],
                                ),
                              );
                              if (result != null)
                                setState(() => weekRange = result);
                            },
                          ),
                        ],
                      ),
                      // 课程背景色
                      _InputGroup(
                        children: [
                          ListTile(
                            title: const Text(
                              '课程背景色',
                              style: TextStyle(fontSize: 16),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    // 这里可以弹出颜色选择器
                                    final result = await showDialog<Color>(
                                      context: context,
                                      builder: (context) => SimpleDialog(
                                        title: const Text('选择颜色'),
                                        children: [
                                          SimpleDialogOption(
                                            onPressed: () => Navigator.pop(
                                              context,
                                              Colors.pinkAccent,
                                            ),
                                            child: const CircleAvatar(
                                              backgroundColor:
                                                  Colors.pinkAccent,
                                            ),
                                          ),
                                          SimpleDialogOption(
                                            onPressed: () => Navigator.pop(
                                              context,
                                              Colors.blueAccent,
                                            ),
                                            child: const CircleAvatar(
                                              backgroundColor:
                                                  Colors.blueAccent,
                                            ),
                                          ),
                                          // 可继续添加更多颜色
                                        ],
                                      ),
                                    );
                                    if (result != null)
                                      setState(() => courseColor = result);
                                  },
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: courseColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 分组容器
class _InputGroup extends StatelessWidget {
  final List<Widget> children;
  const _InputGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }
}

// 单行输入
class _InputRow extends StatelessWidget {
  final String label;
  final String? hint;
  final FormFieldSetter<String>? onSaved;
  final FormFieldValidator<String>? validator;

  const _InputRow({
    required this.label,
    this.hint,
    this.onSaved,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
        ),
        onSaved: onSaved,
        validator: validator,
      ),
    );
  }
}
