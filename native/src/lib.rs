use napi::bindgen_prelude::*;
use napi_derive::napi;

#[napi]
pub fn plus_100(input: u32) -> u32 {
    input + 100
}

#[napi]
pub fn greet(name: String) -> String {
    format!("Hello, {}!", name)
}

#[napi]
pub fn get_num_cpus() -> u32 {
    num_cpus::get() as u32
}

#[napi]
pub fn print_array(arr: Uint8Array) {
    println!("rust arr: '{:?}'", arr.iter());
}

#[cfg(test)]
pub mod test {
    use super::*;

    #[test]
    fn test_plus_100() {
        assert_eq!(plus_100(1), 101);
        assert_eq!(plus_100(200), 300);
        assert_eq!(plus_100(1000), 1100);
    }
}
