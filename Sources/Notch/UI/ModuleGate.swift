import SwiftUI

#if !PRO
/// В простой сборке Pro-модулей нет, поэтому и проверять нечего: панель
/// показывает содержимое как есть. В Pro-сборке то же имя живёт в
/// `Pro/ProGate.swift` и закрывает модули без лицензии.
struct ModuleContentGate: View {
    let module: any NotchModule
    let openSettings: () -> Void

    var body: some View {
        module.erasedContent()
    }
}
#endif
