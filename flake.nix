{
  inputs = {
    # torch 2.0:
    # - optional cuda support: https://github.com/NixOS/nixpkgs/pull/224898
    #
    # rocfft: doesn't cache in hydra (Output limit exceeded)
    # - https://hydra.nixos.org/job/nixpkgs/trunk/rocfft.x86_64-linux
    nixpkgs.url = "github:NixOS/nixpkgs/74c56f2e51d08f0196ed48d32e01d5d408e64451";
  };

  outputs = { self, nixpkgs }@inputs:
    let
      lib = nixpkgs.lib;

      pkgs = import nixpkgs {
        overlays = with self.overlays; [
          default
        ];

        system = "x86_64-linux";
      };
    in
      {
        overlays = {
          default = finalPkgs: prevPkgs: {
            pythonPackagesExtensions = prevPkgs.pythonPackagesExtensions ++ [
              (finalPy: prevPy: {
                # Replaces: https://github.com/NixOS/nixpkgs/pull/214694
                accelerate = finalPy.callPackage (
                  { lib
                  , buildPythonPackage
                  , fetchFromGitHub
                  , numpy
                  , packaging
                  , psutil
                  , pyyaml
                  , torch
                  , evaluate
                  , parameterized
                  , pytest-subtests
                  , pytestCheckHook
                  , transformers
                  }:

                  buildPythonPackage rec {
                    pname = "accelerate";
                    version = "0.18.0";
                    format = "pyproject";

                    src = fetchFromGitHub {
                      owner = "huggingface";
                      repo = "accelerate";
                      rev = "refs/tags/v${version}";
                      hash = "sha256-fCIvVbMaWAWzRfPc5/1CZq3gZ8kruuk9wBt8mzLHmyw=";
                    };

                    propagatedBuildInputs = [
                      numpy
                      packaging
                      psutil
                      pyyaml
                      torch
                    ];

                    nativeCheckInputs = [
                      evaluate
                      parameterized
                      pytest-subtests
                      pytestCheckHook
                      transformers
                    ];

                    preCheck = ''
                      export HOME=$TMPDIR
                      export PATH="$out/bin:$PATH"
                    '';

                    pythonImportsCheck = [
                      "accelerate"
                    ];

                    disabledTests = [
                      # Requires access to HuggingFace to download checkpoints
                      "test_infer_auto_device_map_on_t0pp"
                    ];

                    disabledTestPaths = [
                      # Files under this path are used as scripts in tests,
                      # and shouldn't be treated as pytest sources
                      "src/accelerate/test_utils/scripts"

                      # Requires access to HuggingFace to download checkpoints
                      "tests/test_examples.py"
                    ];

                    meta = with lib; {
                      description = "A simple way to train and use PyTorch models with multi-GPU, TPU, mixed-precision";
                      homepage = "https://github.com/huggingface/accelerate";
                      license = licenses.asl20;
                      maintainers = with maintainers; [ kira-bruneau ];
                    };
                  }
                ) { };

                tokenizers = prevPy.tokenizers.overrideAttrs (finalAttrs: prevAttrs: {
                  version = "0.13.3";

                  src = finalPkgs.fetchFromGitHub {
                    owner = "huggingface";
                    repo = "tokenizers";
                    rev = "refs/tags/python-v${finalAttrs.version}";
                    hash = "sha256-QZG5jmr3vbyQs4mVBjwVDR31O66dUM+p39R0htJ1umk=";
                  };

                  cargoDeps = finalPkgs.rustPlatform.importCargoLock {
                    lockFile = ./Cargo.lock;
                  };

                  postPatch = ''
                    ln -s ${./Cargo.lock} Cargo.lock
                  '';
                });

                transformers = prevPy.transformers.overrideAttrs (finalAttrs: prevAttrs: {
                  version = "4.28.1";

                  src = finalPkgs.fetchFromGitHub {
                    owner = "huggingface";
                    repo = "transformers";
                    rev = "refs/tags/v${finalAttrs.version}";
                    hash = "sha256-FmiuWfoFZjZf1/GbE6PmSkeshWWh+6nDj2u2PMSeDk0=";
                  };
                });
              })
            ];
          };
        };

        devShells."x86_64-linux".default = pkgs.mkShell {
          packages = [
            (pkgs.python3.withPackages (py: with py; [
              accelerate
              fastapi
              # gradio (not packaged: demo server)
              httpx
              markdown2
              numpy
              prompt-toolkit
              pydantic
              requests
              rich
              sentencepiece
              shortuuid
              # tokenizers (not used)
              (lib.hiPrio torchWithRocm)
              transformers
              uvicorn
              # wandb (dev tool only)
            ]))
          ];
        };
      };
}
