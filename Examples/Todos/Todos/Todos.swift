import ComposableArchitecture
import SwiftUI
import Amplify

enum Filter: LocalizedStringKey, CaseIterable, Hashable {
  case all = "All"
  case active = "Active"
  case completed = "Completed"
}

struct AppState: Equatable {
  var editMode: EditMode = .inactive
  var filter: Filter = .all
  var todos: IdentifiedArrayOf<Todo> = []

  var filteredTodos: IdentifiedArrayOf<Todo> {
    switch filter {
    case .active: return self.todos.filter { !$0.isComplete }
    case .all: return self.todos
    case .completed: return self.todos.filter(\.isComplete)
    }
  }
}

enum AppAction: Equatable {
    case addTodoButtonTapped
    case clearCompletedButtonTapped
    case delete(IndexSet)
    case editModeChanged(EditMode)
    case filterPicked(Filter)
    case move(IndexSet, Int)
    case sortCompletedTodos
    case todo(id: Todo.ID, action: TodoAction)
    case todoReceived(_ todo: Todo)
    case subscribeToTodos
}

struct AppEnvironment {
  var mainQueue: AnySchedulerOf<DispatchQueue>
  var uuid: () -> UUID
  var datastore: DataStoreCategory
}

let appReducer = Reducer<AppState, AppAction, AppEnvironment>.combine(
  todoReducer.forEach(
    state: \.todos,
    action: /AppAction.todo(id:action:),
    environment: { _ in TodoEnvironment() }
  ),
  Reducer { state, action, environment in
    switch action {
    case .subscribeToTodos:
        print("Subscribing to Todos")
        // TODO: how to create a long-lived subscription to the data that eventually sends the action
        // .todoReceived(todo)
        return .none
    case .todoReceived(let id):
        print("Received todo \(id)")
        return .none
    case .addTodoButtonTapped:
        let todo = Todo(id: environment.uuid().uuidString, description: "", isComplete: false)
        state.todos.insert(todo, at: 0)
        
        return Effect<AppAction, Never>.future { callback in
            environment.datastore.save(todo) { result in
                switch result {
                case .success(let todo):
                    callback(.success(.todoReceived(todo)))
                case .failure(let error):
                    // TODO: what to do in failure case?
                    callback(.success(.todoReceived(todo)))
                }
            }
        }

    case .clearCompletedButtonTapped:
      state.todos.removeAll(where: \.isComplete)
      return .none

    case let .delete(indexSet):
      state.todos.remove(atOffsets: indexSet)
      return .none

    case let .editModeChanged(editMode):
      state.editMode = editMode
      return .none

    case let .filterPicked(filter):
      state.filter = filter
      return .none

    case var .move(source, destination):
      if state.filter != .all {
        source = IndexSet(
          source
            .map { state.filteredTodos[$0] }
            .compactMap { state.todos.index(id: $0.id) }
        )
        destination =
          state.todos.index(id: state.filteredTodos[destination].id)
          ?? destination
      }

      state.todos.move(fromOffsets: source, toOffset: destination)

      return Effect(value: .sortCompletedTodos)
        .delay(for: .milliseconds(100), scheduler: environment.mainQueue)
        .eraseToEffect()

    case .sortCompletedTodos:
      state.todos.sort { $1.isComplete && !$0.isComplete }
      return .none

    case .todo(id: _, action: .checkBoxToggled):
      struct TodoCompletionId: Hashable {}
      return Effect(value: .sortCompletedTodos)
        .debounce(id: TodoCompletionId(), for: 1, scheduler: environment.mainQueue.animation())

    case .todo:
      return .none
    }
  }
)
.debug()

struct AppView: View {
  let store: Store<AppState, AppAction>
  @ObservedObject var viewStore: ViewStore<ViewState, AppAction>

  init(store: Store<AppState, AppAction>) {
    self.store = store
    self.viewStore = ViewStore(self.store.scope(state: ViewState.init(state:)))
  }

  struct ViewState: Equatable {
    let editMode: EditMode
    let filter: Filter
    let isClearCompletedButtonDisabled: Bool

    init(state: AppState) {
      self.editMode = state.editMode
      self.filter = state.filter
      self.isClearCompletedButtonDisabled = !state.todos.contains(where: \.isComplete)
    }
  }

  var body: some View {
    NavigationView {
      VStack(alignment: .leading) {
        Picker(
          "Filter",
          selection: self.viewStore.binding(get: \.filter, send: AppAction.filterPicked).animation()
        ) {
          ForEach(Filter.allCases, id: \.self) { filter in
            Text(filter.rawValue).tag(filter)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)

        List {
          ForEachStore(
            self.store.scope(state: \.filteredTodos, action: AppAction.todo(id:action:)),
            content: TodoView.init(store:)
          )
          .onDelete { self.viewStore.send(.delete($0)) }
          .onMove { self.viewStore.send(.move($0, $1)) }
        }
      }
      .navigationBarTitle("Todos")
      .navigationBarItems(
        trailing: HStack(spacing: 20) {
          EditButton()
          Button("Clear Completed") {
            self.viewStore.send(.clearCompletedButtonTapped, animation: .default)
          }
          .disabled(self.viewStore.isClearCompletedButtonDisabled)
          Button("Add Todo") { self.viewStore.send(.addTodoButtonTapped, animation: .default) }
        }
      )
      .environment(
        \.editMode,
        self.viewStore.binding(get: \.editMode, send: AppAction.editModeChanged)
      ).onAppear {
          self.viewStore.send(.subscribeToTodos)
      }
    }
    .navigationViewStyle(.stack)
  }
}

extension IdentifiedArray where ID == Todo.ID, Element == Todo {
    
  static let mock: Self = [
    Todo(
        id: "DEADBEEF-DEAD-BEEF-DEAD-BEEDDEADBEEF",
        description: "Check Mail",
        isComplete: false
    ),
    Todo(
        id: "CAFEBEEF-CAFE-BEEF-CAFE-BEEFCAFEBEEF",
        description: "Buy Milk",
        isComplete: false
    ),
    Todo(
        id: "D00DCAFE-D00D-CAFE-D00D-CAFED00DCAFE",
        description: "Call Mom",
        isComplete: true
    ),
  ]
}

struct AppView_Previews: PreviewProvider {
  static var previews: some View {
    AppView(
      store: Store(
        initialState: AppState(todos: .mock),
        reducer: appReducer,
        environment: AppEnvironment(
          mainQueue: .main,
          uuid: UUID.init,
          datastore: Amplify.DataStore
        )
      )
    )
  }
}
