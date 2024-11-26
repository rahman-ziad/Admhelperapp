import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class TodoHomeScreen extends StatefulWidget {
  @override
  _TodoHomeScreenState createState() => _TodoHomeScreenState();
}
class TodoSearchDelegate extends SearchDelegate {
  final List<Map<String, dynamic>> todos;
  final Function(List<Map<String, dynamic>>) onResultSelect;

  TodoSearchDelegate(this.todos, this.onResultSelect);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null); // Close search
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = todos.where((todo) {
      return todo['task'].toLowerCase().contains(query.toLowerCase());
    }).toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text(results[index]['task']),
          subtitle: Text(results[index]['subtitle']),
          onTap: () {
            onResultSelect([results[index]]); // Callback when a result is selected
            close(context, results[index]); // Close search and return result
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final suggestions = todos.where((todo) {
      return todo['task'].toLowerCase().startsWith(query.toLowerCase());
    }).toList();

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text(suggestions[index]['task']),
          subtitle: Text(suggestions[index]['subtitle']),
          onTap: () {
            query = suggestions[index]['task'];
            showResults(context); // Show the result when tapped
          },
        );
      },
    );
  }
}


class _TodoHomeScreenState extends State<TodoHomeScreen> {
  bool isDarkMode = false;
  List<Map<String, dynamic>> todos = [];
  List<Map<String, dynamic>> completedTodos = [];
  TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> filteredTodos = [];


  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    _loadTodos();
  }

  void _loadThemePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  void _loadTodos() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? todoData = prefs.getString('todos');

    if (todoData != null && todoData.isNotEmpty) {
      // Ensure setState is called after the widget is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          List<Map<String, dynamic>> loadedTodos = List<Map<String, dynamic>>.from(json.decode(todoData));

          // Check if category is null for any todo item, if so, set it to default 'Others'
          loadedTodos = loadedTodos.map((todo) {
            if (todo['category'] == null) {
              todo['category'] = 'Others';
            }
            return todo;
          }).toList();

          // Separate completed and remaining todos
          completedTodos = loadedTodos.where((todo) => todo['isComplete'] == true).toList();
          todos = loadedTodos.where((todo) => todo['isComplete'] == false).toList();
        });
      });
    }
  }



  void _saveTodos() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> allTodos = [...todos, ...completedTodos];
    prefs.setString('todos', json.encode(allTodos));
  }
  void _filterTodos(List<Map<String, dynamic>> filteredTodos) {
    setState(() {
      todos = filteredTodos;
    });
  }



  void _addTodo() {
    TextEditingController taskController = TextEditingController();
    TextEditingController subtitleController = TextEditingController();
    TextEditingController descriptionController = TextEditingController();
    String selectedCategory = 'Others';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.8,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Add Todo", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 20),
                    TextField(controller: taskController, decoration: InputDecoration(labelText: 'Task')),
                    TextField(controller: subtitleController, decoration: InputDecoration(labelText: 'Subtitle')),
                    TextField(controller: descriptionController, decoration: InputDecoration(labelText: 'Description')),
                    SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: InputDecoration(labelText: 'Category'),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedCategory = newValue!;
                        });
                      },
                      items: ['Physics', 'Chemistry', 'Biology', 'English', 'Bangla', 'Highermath', 'Others']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,  // For Cancel button background
                            foregroundColor: Colors.white, // Set text color to white
                          ),
                          child: Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              // Insert the new todo at the beginning of the list
                              todos.insert(0, {
                                'task': taskController.text,
                                'subtitle': subtitleController.text,
                                'description': descriptionController.text,
                                'category': selectedCategory,
                                'isComplete': false,
                              });
                            });
                            _saveTodos();
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDarkMode ? const Color(0xff0a7075) : const Color(0xFF0BC8EE),
                            foregroundColor: Colors.white, // Set text color to white
                          ),
                          child: Text('Add'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getPlaceholderImageForCategory(String category) {
    switch (category) {
      case 'Physics':
        return 'https://via.placeholder.com/150/Physics';
      case 'Chemistry':
        return 'https://via.placeholder.com/150/Chemistry';
      case 'Biology':
        return 'https://via.placeholder.com/150/Biology';
      case 'English':
        return 'https://via.placeholder.com/150/English';
      case 'Bangla':
        return 'https://via.placeholder.com/150/Bangla';
      case 'Highermath':
        return 'https://via.placeholder.com/150/Highermath';
      default:
        return 'https://via.placeholder.com/150/Others';
    }
  }

  void _showTaskDetails(Map<String, dynamic> todo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return Container(
          width: double.infinity, // Ensure it fills the width
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                todo['task'],
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                todo['subtitle'],
                style: TextStyle(fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                'Category: ${todo['category']}',
                style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
              ),
              SizedBox(height: 8),
              Text(
                todo['description'],
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              if (todo['category'] != null) // Show the image based on the category
                Image.network(
                  _getPlaceholderImageForCategory(todo['category']),
                  height: 150, // Set the desired height
                  fit: BoxFit.cover,
                ),
            ],
          ),
        );
      },
    );
  }


  void _toggleComplete(int index, bool value) {
    setState(() {
      if (value) {
        // Move to completed
        todos[index]['isComplete'] = true; // Mark as complete
        completedTodos.add(todos[index]);
        todos.removeAt(index);
      } else {
        // Move back to remaining
        completedTodos[index]['isComplete'] = false; // Mark as incomplete
        todos.insert(0, completedTodos[index]); // Insert at the beginning
        completedTodos.removeAt(index);
      }
    });
    _saveTodos();
  }



  void _deleteCompletedTodo(int index) {
    setState(() {
      completedTodos.removeAt(index);
    });
    _saveTodos();
  }

  void _editTodo(Map<String, dynamic> todo, int index) {
    TextEditingController taskController = TextEditingController(text: todo['task']);
    TextEditingController subtitleController = TextEditingController(text: todo['subtitle']);
    TextEditingController descriptionController = TextEditingController(text: todo['description']);
    String selectedCategory = todo['category'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,  // 90% of the screen height
          minChildSize: 0.9,      // Minimum height is also 90% of the screen
          maxChildSize: 1.0,      // Maximum height is full screen (100%)
          builder: (context, scrollController) {
            return Container(
              padding: EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Edit Todo", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 20),
                  TextField(controller: taskController, decoration: InputDecoration(labelText: 'Task')),
                  TextField(controller: subtitleController, decoration: InputDecoration(labelText: 'Subtitle')),
                  TextField(controller: descriptionController, decoration: InputDecoration(labelText: 'Description')),
                  SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: InputDecoration(labelText: 'Category'),
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedCategory = newValue!;
                      });
                    },
                    items: ['Physics', 'Chemistry', 'Biology', 'English', 'Bangla', 'Highermath', 'Others']
                        .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Cancel button action
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey, // For Cancel button background
                          foregroundColor: Colors.white, // For text color
                        ),
                        child: Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            todos[index]['task'] = taskController.text;
                            todos[index]['subtitle'] = subtitleController.text;
                            todos[index]['description'] = descriptionController.text;
                            todos[index]['category'] = selectedCategory;
                          });
                          _saveTodos();
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDarkMode ? const Color(0xff0a7075) : const Color(0xFF0BC8EE),
                          foregroundColor: Colors.white, // Text color is white
                        ),
                        child: Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    String dayOfWeek = DateFormat('EEEE').format(DateTime.now());
    String formattedDate = DateFormat('d MMM').format(DateTime.now());

    return SafeArea(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(isDarkMode ? 'Asset/images/bg_dark.png' : 'Asset/images/bg_light.png'),
              fit: BoxFit.cover,
            ),
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // Align items to the start

            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                title: Text('Todo List'),
                actions: [
                  IconButton(
                    icon: Icon(Icons.search),
                    onPressed: () {
                      try {
                        showSearch(
                          context: context,
                          delegate: TodoSearchDelegate(todos, _filterTodos),
                        );
                      } catch (error) {
                        print('Error: $error');
                      }
                    },
                  ),
                ],
              ),
              SizedBox(
                height: AppBar().preferredSize.height + 20,
                child: Center(
                  child: Text(
                    "$dayOfWeek, $formattedDate",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8.0),
                          child: Text("Remaining Tasks", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            margin: EdgeInsets.zero, // Remove any margin
                            child: SizedBox(
                              height: 3 * 65.0,
                              child: ListView.separated(
                                itemCount: todos.length,
                                separatorBuilder: (context, index) => Divider(height: 1, thickness: 1),
                                itemBuilder: (context, index) {
                                  return GestureDetector(
                                    onLongPress: () => _editTodo(todos[index], index),
                                    child: Container(
                                      alignment: Alignment.topLeft,
                                      child: Dismissible(
                                        key: Key(todos[index]['task']),
                                        background: Container(
                                          color: Colors.red,
                                          alignment: Alignment.centerLeft,
                                          padding: EdgeInsets.only(left: 16),
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete, color: Colors.white),
                                              SizedBox(width: 8),
                                              Text('Delete', style: TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                        direction: DismissDirection.startToEnd,
                                        onDismissed: (direction) {
                                          setState(() {
                                            todos.removeAt(index);
                                          });
                                          _saveTodos();
                                        },
                                        child: ListTile(
                                          leading: Image.network(
                                            _getPlaceholderImageForCategory(todos[index]['category']),
                                            height: 40,
                                            width: 40,
                                            fit: BoxFit.cover,
                                          ),
                                          title: Text(todos[index]['task']),
                                          subtitle: Text(todos[index]['subtitle']),
                                          trailing: Checkbox(
                                            value: false, // Set this to the actual completion status
                                            onChanged: (bool? value) {
                                              _toggleComplete(index, value!); // Move to completed tasks when checked
                                            },
                                          ),
                                          onTap: () {
                                            _showTaskDetails(todos[index]); // Show task details on item tap
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8.0),
                          child: Text("Completed Tasks", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SizedBox(
                              height: 3 * 65.0,
                              child: ListView.separated(
                                itemCount: completedTodos.length,
                                separatorBuilder: (context, index) => Divider(height: 1, thickness: 1),
                                itemBuilder: (context, index) {
                                  return Dismissible(
                                    key: Key(completedTodos[index]['task']),
                                    background: Container(
                                      color: Colors.red,
                                      alignment: Alignment.centerLeft,
                                      padding: EdgeInsets.only(left: 16),
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, color: Colors.white),
                                          SizedBox(width: 8),
                                          Text('Delete', style: TextStyle(color: Colors.white)),
                                        ],
                                      ),
                                    ),
                                    direction: DismissDirection.startToEnd,
                                    onDismissed: (direction) {
                                      _deleteCompletedTodo(index);
                                    },
                                    child: GestureDetector(
                                      onLongPress: () => _editTodo(completedTodos[index], index),
                                      child: ListTile(
                                        leading: Image.network(_getPlaceholderImageForCategory(completedTodos[index]['category'])),
                                        title: Text(completedTodos[index]['task']),
                                        subtitle: Text(completedTodos[index]['subtitle']),
                                        trailing: IconButton(
                                          icon: Icon(Icons.check_box),
                                          onPressed: () => _toggleComplete(index, false), // Move back to remaining
                                        ),
                                        onTap: () => _showTaskDetails(completedTodos[index]), // Optional: Open details on tap
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addTodo,
          child: Icon(Icons.add),
          backgroundColor:isDarkMode? Color(0xff0a7075): Color(0xFF0BC8EE),
        ),
      ),
    );

  }
}
