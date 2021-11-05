//
//  ViewController.swift
//  AsyncSpeech
//
//  Created by andrey.antropov on 04.11.2021.
//

import UIKit
import Combine
import Foundation
import RxSwift
import RxCocoa

class ViewController: UIViewController {
    
    private let button = UIButton(type: .system)
    private let searchBar = UISearchBar()
    private let networkService = NetworkService()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        button.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)
        button.setTitle("Do something", for: [])
        view.addSubview(button)
        button.frame = CGRect(origin: CGPoint(x: 100, y: 200), size: CGSize(width: 150, height: 32))
        
        searchBar.delegate = self
        view.addSubview(searchBar)
        searchBar.frame = CGRect(x: 0, y: 50, width: 320, height: 50)
        
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tap))
        view.addGestureRecognizer(gesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
//        Task {
//            do {
//                let _ = try await networkService.fetchPostsAsync()
//            } catch {
//                print(error)
//            }
//        }
        
        Task {
            for await date in timerStream
                    .map({ $0.timeIntervalSince1970 * 2 })
                    .map({ Date(timeIntervalSince1970: $0) }) {
                print(date)
            }
        }
    }
    
//    override func viewWillAppear(_ animated: Bool) {
//        super.viewWillAppear(animated)
//
//        async let _ = try! networkService.fetchPostsAsync()
//    }
    
    
    
    @objc func tap() {
        searchBar.endEditing(true)
    }
    
    @objc func buttonPressed() {
        Task {
            switch await presentConfirmationAlertAsync() {
            case .ok:
                print("User pressed ok. Proceeding...")
            case .cancel:
                print("User pressed cancel. Cleaning up...")
            }
        }
    }
    
    func presentConfirmationAlert(okHandler: @escaping (() -> Void), cancelHandler: @escaping (() -> Void)) {
        DispatchQueue.main.async { [self] in
            let alertViewController = UIAlertController(title: "Are you sure?", message: nil, preferredStyle: .alert)
            let okAction = UIAlertAction(title: "Ok", style: .destructive) { _ in
                okHandler()
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                cancelHandler()
            }
            
            alertViewController.addAction(okAction)
            alertViewController.addAction(cancelAction)
            
            present(alertViewController, animated: true, completion: nil)
        }
    }
    
    func presentConfirmationAlertAsync() async -> UserConfirmationActionType {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alertViewController = UIAlertController(title: "Are you sure?", message: nil, preferredStyle: .alert)
                let okAction = UIAlertAction(title: "Ok", style: .destructive) { _ in
                    continuation.resume(with: .success(UserConfirmationActionType.ok))
                }
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    continuation.resume(with: .success(UserConfirmationActionType.cancel))
                }
                
                alertViewController.addAction(okAction)
                alertViewController.addAction(cancelAction)
                
                self.present(alertViewController, animated: true, completion: nil)
            }
        }
    }
}

extension ViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let searchBarTextStream = AsyncStream { stream in
            stream.yield(searchText)
        }
        Task {
            for await searchText in searchBarTextStream {
                print("User searched for \(searchText)")
            }
        }
    }
}

enum UserConfirmationActionType {
    case ok
    case cancel
}

class NetworkService {
    let url = URL(string: "https://jsonplaceholder.typicode.com/posts")!
    
    func fetchPosts(completion: @escaping ((Result<[Post], Error>) -> Void)) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let posts = try? JSONDecoder().decode(Array<Post>.self, from: data) {
                completion(.success(posts))
            } else {
                completion(.failure(MyError.somethingWentWrong))
            }
        }
    }
    
    func fetchViewModels(completion: @escaping ((Result<[PostViewModel], Error>) -> Void)) {
        fetchPosts { result in
            switch result {
            case .success(let posts):
                var viewModels: [PostViewModel] = []
                viewModels.reserveCapacity(posts.count)
                
                let dispatchGroup = DispatchGroup()
                
                for post in posts {
                    if let imageUrl = URL(string: post.imageUrlString) {
                        dispatchGroup.enter()
                        
                        URLSession.shared.dataTask(with: imageUrl) { data, _, _ in
                            let image = data.flatMap(UIImage.init)
                            viewModels.append(PostViewModel(post: post, postImage: image))
                            dispatchGroup.leave()
                        }.resume()
                    } else {
                        viewModels.append(PostViewModel(post: post, postImage: nil))
                    }
                }
                
                dispatchGroup.notify(queue: DispatchQueue.main) {
                    completion(.success(viewModels))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func fetchPostsCombine() -> AnyPublisher<[Post], MyError> {
        URLSession.shared
            .dataTaskPublisher(for: url)
            .tryMap { try JSONDecoder().decode(Array<Post>.self, from: $0.0) }
            .mapError { _ in MyError.somethingWentWrong }
            .eraseToAnyPublisher()
    }
    
    func fetchPostsRx() -> Observable<[Post]> {
        URLSession.shared.rx
            .response(request: URLRequest(url: url))
            .compactMap { try JSONDecoder().decode(Array<Post>.self, from: $0.data) }
    }
    
    func fetchPostsWithTask(completion: @escaping ((Result<[Post], Error>) -> Void)) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let posts = try JSONDecoder().decode(Array<Post>.self, from: data)
                completion(.success(posts))
            } catch {
                completion(.failure(MyError.somethingWentWrong))
            }
        }
    }
    
    func fetchPostsAsync() async throws -> [Post] {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Array<Post>.self, from: data)
    }
    
    func fetchPostViewModelsForLoop() async throws -> [PostViewModel] {
        let posts = try await fetchPostsAsync()
        
        var viewModels = [PostViewModel]()
        viewModels.reserveCapacity(posts.count)
        
        for post in posts {
            guard let imageUrl = URL(string: post.imageUrlString),
                  let (imageData, _) = try? await URLSession.shared.data(from: imageUrl),
                  let image = UIImage(data: imageData) else { continue }
            viewModels.append(PostViewModel(post: post, postImage: image))
        }
        
        return viewModels
    }
    
    func fetchPostViewModelsAsync() async throws -> [PostViewModel] {
        let posts = try await fetchPostsAsync()
        
        var viewModels: [PostViewModel] = []
        
        try await withThrowingTaskGroup(of: PostViewModel.self, body: { taskGroup in
            for post in posts {
                if let imageUrl = URL(string: post.imageUrlString) {
                    taskGroup.addTask {
                        let (imageData, _) = try await URLSession.shared.data(from: imageUrl)
                        return PostViewModel(post: post, postImage: UIImage(data: imageData))
                    }
                } else {
                    viewModels.append(PostViewModel(post: post, postImage: nil))
                }
            }
            
            for try await viewModel in taskGroup {
                viewModels.append(viewModel)
            }
        })
        
        return viewModels
    }
    
    func fetchPostViewModelsCombine() -> AnyPublisher<[PostViewModel], MyError> {
        fetchPostsCombine()
            .flatMap { posts in
                return Publishers.MergeMany(
                    posts.map { (post: Post) -> AnyPublisher<PostViewModel, MyError> in
                        guard let imageUrl = URL(string: post.imageUrlString) else {
                            return Just(PostViewModel(post: post, postImage: nil))
                            .setFailureType(to: MyError.self)
                            .eraseToAnyPublisher()
                        }
                        return URLSession.shared.dataTaskPublisher(for: imageUrl)
                            .map { UIImage(data: $0.data) }
                            .map { PostViewModel(post: post, postImage: $0) }
                            .mapError { _ in MyError.somethingWentWrong }
                            .eraseToAnyPublisher()
                    }
                ).collect()
            }.eraseToAnyPublisher()
    }
    
    func fetchPostViewModelsRxSwift() -> Observable<[PostViewModel]> {
        fetchPostsRx()
            .flatMap { posts in
                return Observable.merge(
                    posts.map { post in
                        guard let imageUrl = URL(string: post.imageUrlString) else {
                            return .just(.init(post: post, postImage: nil))
                        }
                        let imagePublisher = URLSession.shared.rx.response(request: URLRequest(url: imageUrl))
                            .map(\.data)
                            .compactMap(UIImage.init)
                        return imagePublisher.map { PostViewModel(post: post, postImage: $0) }
                    }
                ).toArray()
            }
    }
}

struct Post: Codable {
    let userId: Int
    let id: Int
    let title: String
    let body: String
    let imageUrlString: String
}

struct PostViewModel {
    let post: Post
    let postImage: UIImage?
}

enum MyError: Error {
    case somethingWentWrong
}

    let timerStream = AsyncStream<Date> { stream in
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true)  { _ in
            stream.yield(Date())
        }
        
        stream.onTermination = { @Sendable termination in
            switch termination {
            case .finished, .cancelled:
                timer.invalidate()
            @unknown default:
                timer.invalidate()
            }
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            stream.finish()
        }
    }
