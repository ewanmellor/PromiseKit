import Dispatch

public protocol CatchMixin: Thenable
{}

public extension CatchMixin {
    @discardableResult
    func `catch`(on: DispatchQueue? = conf.Q.return, policy: CatchPolicy = conf.catchPolicy, _ body: @escaping(Error) -> Void) -> PMKFinalizer {
        let finalizer = PMKFinalizer()
        pipe {
            switch $0 {
            case .fulfilled:
                finalizer.pending.resolve()
            case .rejected(let error):
                if policy == .allErrors || !error.isCancelled {
                    on.async{
                        body(error)
                        finalizer.pending.resolve()
                    }
                }
            }
        }
        return finalizer
    }

    func recover<U: Thenable>(on: DispatchQueue? = conf.Q.map, policy: CatchPolicy = conf.catchPolicy, _ body: @escaping(Error) throws -> U) -> Promise<T> where U.T == T {
        let rp = Promise<U.T>(.pending)
        pipe {
            switch $0 {
            case .fulfilled(let value):
                rp.box.seal(.fulfilled(value))
            case .rejected(let error):
                if policy == .allErrors || !error.isCancelled {
                    on.async {
                        do {
                            let rv = try body(error)
                            guard rv !== rp else { throw PMKError.returnedSelf }
                            rv.pipe(to: rp.box.seal)
                        } catch {
                            rp.box.seal(.rejected(error))
                        }
                    }
                } else {
                    rp.box.seal(.rejected(error))
                }
            }
        }
        return rp
    }

    func ensure(on: DispatchQueue? = conf.Q.return, _ body: @escaping () -> Void) -> Promise<T> {
        let rp = Promise<T>(.pending)
        pipe { result in
            on.async {
                body()
                rp.box.seal(result)
            }
        }
        return rp
    }

    func cauterize() {
        self.catch {
            print("PromiseKit:cauterized-error:", $0)
        }
    }
}

public class PMKFinalizer {
    let pending = Guarantee<Void>.pending()

    public func finally(_ body: @escaping () -> Void) {
        pending.guarantee.done(body)
    }
}
