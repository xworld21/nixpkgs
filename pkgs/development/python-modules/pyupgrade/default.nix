{ buildPythonPackage
, fetchFromGitHub
, isPy27
, lib
, pytestCheckHook
, tokenize-rt
}:

buildPythonPackage rec {
  pname = "pyupgrade";
  version = "2.20.0";
  disabled = isPy27;

  src = fetchFromGitHub {
    owner = "asottile";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-Wq15JU6sbXPZSk/vAX6fTuc3vxZeRy9dSCNGGv2utY4=";
  };

  checkInputs = [ pytestCheckHook ];

  propagatedBuildInputs = [ tokenize-rt ];

  pythonImportsCheck = [ "pyupgrade" ];

  meta = with lib; {
    description = "Tool to automatically upgrade syntax for newer versions of the language";
    homepage = "https://github.com/asottile/pyupgrade";
    license = licenses.mit;
    maintainers = with maintainers; [ lovesegfault ];
  };
}
