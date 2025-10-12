import 'package:flutter/material.dart';
import 'table/add_course_dialog.dart';

class TablePage extends StatefulWidget {
  const TablePage({super.key});

  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  // 周数与日期
  int currentWeek = 1;
  final int maxWeek = 20;
  final List<String> weekDays = ['一', '二', '三', '四', '五'];
  final List<String> dates = ['3/10', '3/11', '3/12', '3/13', '3/14'];
  // 课程数据结构
  final int rowCount = 9;
  final int colCount = 5;
  List<List<Map<String, dynamic>?>> tableData = List.generate(
    9,
    (_) => List.filled(5, null),
  );

  // 选中的格子
  int? selectedRow;
  int? selectedCol;

  // 滑动控制
  final PageController _pageController = PageController(initialPage: 0);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onAddTap() {
    print('onAddTap: $selectedRow, $selectedCol');
    if (selectedRow != null && selectedCol != null) {
      _showAddCourseDialog(selectedRow!, selectedCol!);
    }
  }

  void _showAddCourseDialog(int row, int col) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AddCourseDialog(),
    );
    if (result != null) {
      setState(() {
        tableData[row][col] = result;
        selectedRow = null;
        selectedCol = null;
      });
    }
  }

  void _onCellTap(int row, int col) {
    setState(() {
      selectedRow = row;
      selectedCol = col;
    });
  }

  void _onPageChanged(int page) {
    setState(() {
      currentWeek = page + 1;
      // 可根据需要更新dates
    });
  }

  @override
  Widget build(BuildContext context) {
    print('AddCourseDialog build');
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '课程表',
          style: TextStyle(fontFamily: 'MiSans', fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.menu), onPressed: () {})],
      ),
      body: Column(
        children: [
          // 周选择与日期
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                DropdownButton<int>(
                  value: currentWeek,
                  items: List.generate(
                    maxWeek,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text('${i + 1} 周'),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        currentWeek = v;
                        _pageController.jumpToPage(v - 1);
                      });
                    }
                  },
                ),
                const SizedBox(width: 16),
                ...List.generate(
                  weekDays.length,
                  (i) => Expanded(
                    child: Column(
                      children: [
                        Text(
                          weekDays[i],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          dates[i],
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: maxWeek,
              itemBuilder: (context, pageIndex) {
                return _buildTable();
              },
            ),
          ),
        ],
      ),
      floatingActionButton: selectedRow != null && selectedCol != null
          ? FloatingActionButton(
              onPressed: _onAddTap,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildTable() {
    return Table(
      border: TableBorder.all(color: Colors.grey.shade200),
      children: [
        for (int row = 0; row < rowCount; row++)
          TableRow(
            children: [
              // 节次时间
              Container(
                height: 60,
                color: Colors.white,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${row + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _getTimeRange(row),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              ...List.generate(colCount, (col) {
                final isSelected = selectedRow == row && selectedCol == col;
                final course = tableData[row][col];
                return GestureDetector(
                  onTap: () => _onCellTap(row, col),
                  child: Container(
                    height: 60,
                    color: isSelected ? Colors.grey.shade200 : Colors.white,
                    alignment: Alignment.center,
                    // 在格子有课程时显示全部信息
                    child: course == null
                        ? isSelected
                              ? GestureDetector(
                                  onTap: () => _showAddCourseDialog(row, col),
                                  child: const Icon(
                                    Icons.add,
                                    size: 32,
                                    color: Colors.grey,
                                  ),
                                )
                              : null
                        : Container(
                            decoration: BoxDecoration(
                              color: course['courseColor'] ?? Colors.blueAccent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  course['name'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if ((course['teacher'] ?? '').isNotEmpty)
                                  Text(
                                    course['teacher'],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                if ((course['classroom'] ?? '').isNotEmpty)
                                  Text(
                                    course['classroom'],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                Text(
                                  '时间${course['timeIndex'] ?? ''}  ${course['weekRange'] ?? ''}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                );
              }),
            ],
          ),
      ],
    );
  }

  String _getTimeRange(int row) {
    // 可根据实际需求调整
    const times = [
      '08:30\n09:15',
      '09:25\n10:10',
      '10:20\n11:05',
      '11:15\n12:00',
      '14:00\n14:45',
      '14:55\n15:40',
      '15:50\n16:35',
      '16:45\n17:30',
      '19:00\n19:45',
    ];
    return times[row];
  }
}
