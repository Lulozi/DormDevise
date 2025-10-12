import 'package:dormdevise/screen/openDoorPage/open_door.dart';
import 'package:dormdevise/screen/personPage/person.dart';
import 'package:dormdevise/screen/tablePage/table.dart';
import 'package:flutter/material.dart';

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  _ManagementScreenState createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  int selectedIndex = 1;
  final PageController _pageController = PageController(initialPage: 1);
  final List<Widget> pages = [
    const TablePage(),
    const OpenDoorPage(),
    const PersonPage(),
  ];
  // FIXME 流畅度需要优化
  // MAYBE 更好看的页面切换效果
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          elevation: 0,
          backgroundColor: const Color(0xFFf9f9fc),
          unselectedItemColor: Colors.grey,
          selectedItemColor: Colors.black,
          type: BottomNavigationBarType.fixed,
          currentIndex: selectedIndex,
          onTap: (value) {
            setState(() {
              selectedIndex = value;
              _pageController.animateToPage(
                value,
                // HACK 延长动画时间以提升流畅度
                duration: const Duration(milliseconds: 500),
                curve: Curves.ease,
              );
            });
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(
                selectedIndex == 0
                    ? Icons.calendar_today
                    : Icons.calendar_today_outlined,
                size: selectedIndex == 0 ? 28 : 24,
              ),
              label: "",
            ),
            BottomNavigationBarItem(
              icon: Icon(
                selectedIndex == 1
                    ? Icons.door_front_door
                    : Icons.door_front_door_outlined,
                size: selectedIndex == 1 ? 28 : 24,
              ),
              label: "",
            ),
            BottomNavigationBarItem(
              icon: Icon(
                selectedIndex == 2 ? Icons.person : Icons.person_outline,
                size: selectedIndex == 2 ? 28 : 24,
              ),
              label: "",
            ),
          ],
        ),
      ),
      body: PageView(
        controller: _pageController,
        children: pages,
        onPageChanged: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
      ),
    );
  }
}
